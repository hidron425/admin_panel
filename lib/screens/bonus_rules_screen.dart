import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:admin_panel/utils/audit.dart';
import 'package:admin_panel/utils/app_state.dart';

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
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  String? _selectedMallId;
  List<Map<String, dynamic>> _rules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedMallId = AppState.selectedMallId.value;
    AppState.selectedMallId.addListener(_onMallChanged);
    _loadRules();
  }

  @override
  void dispose() {
    AppState.selectedMallId.removeListener(_onMallChanged);
    super.dispose();
  }

  void _onMallChanged() {
    if (_selectedMallId != AppState.selectedMallId.value) {
      setState(() => _selectedMallId = AppState.selectedMallId.value);
      _loadRules();
    }
  }

  bool _ruleAppliesToMall(Map<String, dynamic> data) {
    final ruleMallId = data['mall_id'] as String?;
    if (_selectedMallId == null) return true;
    return ruleMallId == null || ruleMallId.isEmpty || ruleMallId == _selectedMallId;
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    try {
      final data = await _sb
          .from('bonus_rules')
          .select()
          .order('created_at', ascending: false);
      final all = (data as List)
          .map((json) => Map<String, dynamic>.from(json))
          .toList();
      if (mounted) {
        setState(() {
          _rules = all.where(_ruleAppliesToMall).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadRules: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showRuleDialog({String? ruleId, Map<String, dynamic>? existing}) async {
    final isEdit = ruleId != null;
    final formKey = GlobalKey<FormState>();

    final reward = (existing?['reward'] as Map<String, dynamic>?) ?? {};
    final rewardTitleCtrl = TextEditingController(text: reward['title'] ?? '');
    final rewardMsgCtrl = TextEditingController(text: reward['message'] ?? '');
    final rewardIconCtrl = TextEditingController(text: reward['icon'] ?? '🎁');
    final rewardShopCtrl = TextEditingController(text: reward['targetShopId'] ?? '');

    String selectedTrigger = existing?['trigger'] ?? 'step_completed';
    bool oncePerUser = existing?['once_per_user'] ?? true;
    bool active = existing?['active'] ?? true;
    final existingMallId = existing?['mall_id'] as String?;
    bool isCommon = existingMallId == null || existingMallId.isEmpty;

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
                    DropdownButtonFormField<String>(
                      value: selectedTrigger,
                      decoration: const InputDecoration(labelText: 'Триггер'),
                      items: triggerOptions
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedTrigger = v!),
                    ),
                    const SizedBox(height: 16),
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
                              onChanged: (v) => setDialogState(
                                  () => conditions[i] = MapEntry(v!, conditions[i].value)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: conditions[i].value,
                              decoration: const InputDecoration(labelText: 'Значение'),
                              onChanged: (v) => setDialogState(
                                  () => conditions[i] = MapEntry(conditions[i].key, v)),
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
                      onPressed: () => setDialogState(
                          () => conditions.add(const MapEntry('stepCount', '1'))),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
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
                    SwitchListTile(
                      title: const Text('Общее правило (для всех ТЦ)'),
                      subtitle: const Text('Если включено, правило не привязано к конкретному ТЦ'),
                      value: isCommon,
                      onChanged: (v) => setDialogState(() => isCommon = v),
                    ),
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
                  final data = <String, dynamic>{
                    'trigger': selectedTrigger,
                    'conditions': Map.fromEntries(conditions),
                    'reward': {
                      'title': rewardTitleCtrl.text.trim(),
                      'message': rewardMsgCtrl.text.trim(),
                      'icon': rewardIconCtrl.text.trim(),
                      'targetShopId': rewardShopCtrl.text.trim(),
                    },
                    'once_per_user': oncePerUser,
                    'active': active,
                    'mall_id': isCommon ? null : _selectedMallId,
                  };

                  try {
                    if (isEdit) {
                      await _sb.from('bonus_rules').update(data).eq('id', ruleId);
                      AuditLogger.log(
                        action: 'update',
                        collection: 'bonus_rules',
                        docId: ruleId,
                        changes: data,
                      );
                    } else {
                      data['created_at'] = DateTime.now().toIso8601String();
                      final result = await _sb
                          .from('bonus_rules')
                          .insert(data)
                          .select('id')
                          .single();
                      AuditLogger.log(
                        action: 'create',
                        collection: 'bonus_rules',
                        docId: result['id'].toString(),
                        changes: data,
                      );
                    }
                    if (mounted) Navigator.pop(ctx);
                    _loadRules();
                  } catch (e) {
                    debugPrint('❌ save rule: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  }
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }

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
      try {
        await _sb.from('bonus_rules').delete().eq('id', id);
        AuditLogger.log(action: 'delete', collection: 'bonus_rules', docId: id);
        _loadRules();
      } catch (e) {
        debugPrint('❌ delete rule: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedMallId == null
            ? 'Бонусные правила (Все ТЦ)'
            : 'Бонусные правила (${_selectedMallId})'),
        leading: IconButton(
          icon: const Icon(Icons.add, color: Color(0xFF6C63FF)),
          tooltip: 'Добавить правило',
          onPressed: () => _showRuleDialog(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? const Center(child: Text('Нет правил'))
              : ListView.builder(
                  itemCount: _rules.length,
                  itemBuilder: (context, index) {
                    final data = _rules[index];
                    final id = data['id'].toString();
                    final reward = (data['reward'] as Map<String, dynamic>?) ?? {};
                    final conditions = (data['conditions'] as Map<String, dynamic>?) ?? {};
                    final trigger = data['trigger'] ?? '?';
                    final once = data['once_per_user'] == true;
                    final active = data['active'] == true;
                    final mallId = data['mall_id'] as String?;
                    final mallLabel = (mallId == null || mallId.isEmpty) ? 'Общее' : mallId;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ExpansionTile(
                        title: Text(reward['title'] ?? 'Без названия'),
                        subtitle: Text('$trigger ${active ? "✅" : "⛔"} | ТЦ: $mallLabel'),
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
                                      onPressed: () => _showRuleDialog(ruleId: id, existing: data),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteRule(id),
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
                ),
    );
  }
}