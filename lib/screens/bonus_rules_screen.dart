import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:admin_panel/utils/audit.dart';   // 🆕 сервис аудита

class BonusRulesScreen extends StatefulWidget {
  const BonusRulesScreen({Key? key}) : super(key: key);

  @override
  State<BonusRulesScreen> createState() => _BonusRulesScreenState();
}

class _BonusRulesScreenState extends State<BonusRulesScreen> {
  final _firestore = FirebaseFirestore.instance;

  // ---------- Создание правила ----------
  Future<void> _addRule() async {
    final sponsorCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final stepsCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить бонусное правило'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: sponsorCtrl, decoration: const InputDecoration(labelText: 'ID магазина-спонсора')),
              TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'ID магазина-бонуса')),
              TextField(controller: stepsCtrl, decoration: const InputDecoration(labelText: 'Шагов (например 5)'), keyboardType: TextInputType.number),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание бонуса')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              final data = {
                'sponsorShopId': sponsorCtrl.text.trim(),
                'targetShopId': targetCtrl.text.trim(),
                'requiredSteps': int.tryParse(stepsCtrl.text) ?? 5,
                'bonusDescription': descCtrl.text.trim(),
                'active': true,
              };
              final docRef = await _firestore.collection('bonus_rules').add(data);
              // 🆕 Аудит создания
              AuditLogger.log(
                action: 'create',
                collection: 'bonus_rules',
                docId: docRef.id,
                changes: data,
              );
              Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  // ---------- Редактирование правила ----------
  Future<void> _editRule(String id, Map<String, dynamic> data) async {
    final sponsorCtrl = TextEditingController(text: data['sponsorShopId']);
    final targetCtrl = TextEditingController(text: data['targetShopId']);
    final stepsCtrl = TextEditingController(text: data['requiredSteps'].toString());
    final descCtrl = TextEditingController(text: data['bonusDescription']);
    bool active = data['active'] ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Редактировать правило'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: sponsorCtrl, decoration: const InputDecoration(labelText: 'ID спонсора')),
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'ID бонусного магазина')),
                TextField(controller: stepsCtrl, decoration: const InputDecoration(labelText: 'Шагов'), keyboardType: TextInputType.number),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание')),
                SwitchListTile(
                  title: const Text('Активно'),
                  value: active,
                  onChanged: (val) => setStateDialog(() => active = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final updatedData = {
                  'sponsorShopId': sponsorCtrl.text.trim(),
                  'targetShopId': targetCtrl.text.trim(),
                  'requiredSteps': int.tryParse(stepsCtrl.text) ?? 5,
                  'bonusDescription': descCtrl.text.trim(),
                  'active': active,
                };
                await _firestore.collection('bonus_rules').doc(id).update(updatedData);
                // 🆕 Аудит редактирования
                AuditLogger.log(
                  action: 'update',
                  collection: 'bonus_rules',
                  docId: id,
                  changes: updatedData,
                );
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Удаление правила ----------
  Future<void> _deleteRule(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить правило?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('bonus_rules').doc(id).delete();
      // 🆕 Аудит удаления
      AuditLogger.log(
        action: 'delete',
        collection: 'bonus_rules',
        docId: id,
      );
    }
  }

  // ---------- UI: список правил ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Бонусные правила'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addRule,
          ),
        ],
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
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(data['bonusDescription'] ?? ''),
                  subtitle: Text(
                    'Спонсор: ${data['sponsorShopId']} → Бонус: ${data['targetShopId']} | Шагов: ${data['requiredSteps']} | ${data['active'] == true ? "Активно" : "Неактивно"}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editRule(doc.id, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteRule(doc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}