import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:admin_panel/utils/audit.dart';

// Типы условий и триггеров
const List<String> triggerOptions = [
  'step_completed',
  'cycle_completed',
  'collab_activated',
];

const Map<String, String> conditionTypes = {
  'stepCount': 'Конкретный шаг (1-5)',
  'cycleCount': 'Номер цикла',
  'minStepsCompleted': 'Минимальное число шагов',
  'shopId': 'ID магазина',
  'category': 'Категория магазина',
};

class BonusRulesScreen extends StatefulWidget {
  const BonusRulesScreen({Key? key}) : super(key: key);

  @override
  State<BonusRulesScreen> createState() => _BonusRulesScreenState();
}

class _BonusRulesScreenState extends State<BonusRulesScreen> {
  final _firestore = FirebaseFirestore.instance;

  // ---------- Открыть диалог добавления / редактирования ----------
  Future<void> _showRuleDialog({String? ruleId, Map<String, dynamic>? existing}) async {
    final isEdit = ruleId != null;
    final formKey = GlobalKey<FormState>();

    // Контроллеры для reward
    final rewardTitleCtrl = TextEditingController(text: existing?['reward']?['title'] ?? '');
    final rewardMsgCtrl = TextEditingController(text: existing?['reward']?['message'] ?? '');
    final rewardIconCtrl = TextEditingController(text: existing?['reward']?['icon'] ?? '🎁');
    final rewardShopCtrl = TextEditingController(text: existing?['reward']?['targetShopId'] ?? '');

    // Выбранный триггер
    String selectedTrigger = existing?['trigger'] ?? 'step_completed';
    bool oncePerUser = existing?['oncePerUser'] ?? true;
    bool active = existing?['active'] ?? true;

    // Список условий (редактируемый)
    List<MapEntry<String, String>> conditions = [];
    final existingCond = existing?['conditions'] as Map<String, dynamic>?;
    if (existingCond != null) {
      existingCond.forEach((key, value) {
        conditions.add(MapEntry(key, value.toString()));
      });
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? 'Редактировать правило' : 'Новое правило'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ----- ТРИГГЕР -----
                    DropdownButtonFormField<String>(
                      value: selectedTrigger,
                      decoration: const InputDecoration(labelText: 'Триггер'),
                      items: triggerOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (v) => setDialogState(() => selectedTrigger = v!),
                    ),
                    const SizedBox(height: 16),

                    // ----- УСЛОВИЯ -----
                    const Text('Условия срабатывания', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...List.generate(conditions.length, (i) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: conditions[i].key,
                              decoration: const InputDecoration(labelText: 'Тип'),
                              items: conditionTypes.entries
                                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                                  .toList(),
                              onChanged: (v) => setDialogState(() => conditions[i] = MapEntry(v!, conditions[i].value)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: conditions[i].value,
                              decoration: const InputDecoration(labelText: 'Значение'),
                              onChanged: (v) => setDialogState(() => conditions[i] = MapEntry(conditions[i].key, v)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                            onPressed: () => setDialogState(() => conditions.removeAt(i)),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить условие'),
                      onPressed: () => setDialogState(() => conditions.add(const MapEntry('stepCount', '1'))),
                    ),

                    const SizedBox(height: 16),
                    const Divider(),
                    // ----- НАГРАДА -----
                    const Text('Награда', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: rewardTitleCtrl,
                      decoration: const InputDecoration(labelText: 'Название'),
                    ),
                    TextFormField(
                      controller: rewardMsgCtrl,
                      decoration: const InputDecoration(labelText: 'Описание'),
                      maxLines: 2,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: rewardIconCtrl,
                            decoration: const InputDecoration(labelText: 'Иконка'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: rewardShopCtrl,
                            decoration: const InputDecoration(labelText: 'ID бонусного магазина'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Однократно'),
                        Switch(
                          value: oncePerUser,
                          onChanged: (v) => setDialogState(() => oncePerUser = v),
                        ),
                        const Spacer(),
                        const Text('Активно'),
                        Switch(
                          value: active,
                          onChanged: (v) => setDialogState(() => active = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () async {
                  final data = {
                    'trigger': selectedTrigger,
                    'conditions': Map.fromEntries(conditions),
                    'reward': {
                      'title': rewardTitleCtrl.text.trim(),
                      'message': rewardMsgCtrl.text.trim(),
                      'icon': rewardIconCtrl.text.trim(),
                      'targetShopId': rewardShopCtrl.text.trim(),
                    },
                    'oncePerUser': oncePerUser,
                    'active': active,
                  };

                  if (isEdit) {
                    await _firestore.collection('bonus_rules').doc(ruleId).update(data);
                    AuditLogger.log(action: 'update', collection: 'bonus_rules', docId: ruleId, changes: data);
                  } else {
                    final ref = await _firestore.collection('bonus_rules').add(data);
                    AuditLogger.log(action: 'create', collection: 'bonus_rules', docId: ref.id, changes: data);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------- Удаление ----------
  Future<void> _deleteRule(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить правило?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('bonus_rules').doc(id).delete();
      AuditLogger.log(action: 'delete', collection: 'bonus_rules', docId: id);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: const Text('Бонусные правила'),
  leading: IconButton(
    icon: const Icon(Icons.add, color: Color(0xFF6C63FF)), // фиолетовый значок
    tooltip: 'Добавить правило',
    onPressed: () => _showRuleDialog(),
          ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('bonus_rules').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Ошибка: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Нет правил'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final reward = data['reward'] as Map<String, dynamic>? ?? {};
              final conditions = data['conditions'] as Map<String, dynamic>? ?? {};
              final trigger = data['trigger'] ?? '?';
              final once = data['oncePerUser'] == true;
              final active = data['active'] == true;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ExpansionTile(
                  title: Text(reward['title'] ?? 'Без названия'),
                  subtitle: Text('$trigger ${active ? "✅" : "⛔"}'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Условия: ${conditions.isNotEmpty ? conditions.toString() : "нет"}'),
                          const SizedBox(height: 8),
                          Text('Награда: ${reward['message'] ?? ""}'),
                          Text('Иконка: ${reward['icon'] ?? "🎁"}'),
                          Text('Магазин: ${reward['targetShopId'] ?? "не указан"}'),
                          const SizedBox(height: 8),
                          Text('Однократно: $once'),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _showRuleDialog(ruleId: doc.id, existing: data),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteRule(doc.id),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}