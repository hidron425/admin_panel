import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BonusRulesScreen extends StatefulWidget {
  const BonusRulesScreen({Key? key}) : super(key: key);

  @override
  State<BonusRulesScreen> createState() => _BonusRulesScreenState();
}

class _BonusRulesScreenState extends State<BonusRulesScreen> {
  final _firestore = FirebaseFirestore.instance;

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
              await _firestore.collection('bonus_rules').add({
                'sponsorShopId': sponsorCtrl.text.trim(),
                'targetShopId': targetCtrl.text.trim(),
                'requiredSteps': int.tryParse(stepsCtrl.text) ?? 5,
                'bonusDescription': descCtrl.text.trim(),
                'active': true,
              });
              Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

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
                await _firestore.collection('bonus_rules').doc(id).update({
                  'sponsorShopId': sponsorCtrl.text.trim(),
                  'targetShopId': targetCtrl.text.trim(),
                  'requiredSteps': int.tryParse(stepsCtrl.text) ?? 5,
                  'bonusDescription': descCtrl.text.trim(),
                  'active': active,
                });
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Бонусные правила')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('bonus_rules').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rules = snapshot.data!.docs;
          if (rules.isEmpty) {
            return const Center(child: Text('Нет бонусных правил'));
          }
          return ListView.builder(
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final doc = rules[index];
              final data = doc.data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(data['bonusDescription'] ?? 'Без описания'),
                  subtitle: Text('Шагов: ${data['requiredSteps']} | Спонсор: ${data['sponsorShopId']} → ${data['targetShopId']}'),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addRule,
        child: const Icon(Icons.add),
      ),
    );
  }
}