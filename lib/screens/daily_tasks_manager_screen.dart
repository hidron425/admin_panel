import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:admin_panel/utils/audit.dart';

class DailyTasksManagerScreen extends StatefulWidget {
  const DailyTasksManagerScreen({super.key});

  @override
  State<DailyTasksManagerScreen> createState() => _DailyTasksManagerScreenState();
}

class _DailyTasksManagerScreenState extends State<DailyTasksManagerScreen> {
  final _firestore = FirebaseFirestore.instance;

  Future<void> _addOrEditTask({String? taskId, Map<String, dynamic>? existing}) async {
    final isEdit = taskId != null;
    final formKey = GlobalKey<FormState>();

    String selectedType = existing?['type'] ?? 'complete_quest';
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final rewardCtrl = TextEditingController(text: existing?['reward']?.toString() ?? '50');
    final targetCtrl = TextEditingController(text: existing?['target']?.toString() ?? '1');
    String? category;
    if (existing?['category'] != null) {
      category = existing!['category'] as String;
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Редактировать задание' : 'Новое задание'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: 'Тип задания'),
                    items: [
                      DropdownMenuItem(value: 'complete_quest', child: Text('Завершить квест')),
                      DropdownMenuItem(value: 'visit_category', child: Text('Посетить категорию')),
                      DropdownMenuItem(value: 'invite_friend', child: Text('Пригласить друга')),
                    ],
                    onChanged: (v) => setDialogState(() => selectedType = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Описание задания'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: rewardCtrl,
                    decoration: const InputDecoration(labelText: 'Награда (монет)'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: targetCtrl,
                    decoration: const InputDecoration(labelText: 'Цель (сколько раз выполнить)'),
                    keyboardType: TextInputType.number,
                  ),
                  if (selectedType == 'visit_category') ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Категория магазина'),
                      onChanged: (v) => category = v.trim(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'type': selectedType,
                  'description': descCtrl.text.trim(),
                  'reward': int.tryParse(rewardCtrl.text) ?? 50,
                  'target': int.tryParse(targetCtrl.text) ?? 1,
                  'category': selectedType == 'visit_category' ? category : null,
                  'active': true,
                };
                if (isEdit) {
                  await _firestore.collection('daily_tasks').doc(taskId).update(data);
                  AuditLogger.log(action: 'update', collection: 'daily_tasks', docId: taskId, changes: data);
                } else {
                  final ref = await _firestore.collection('daily_tasks').add(data);
                  AuditLogger.log(action: 'create', collection: 'daily_tasks', docId: ref.id, changes: data);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTask(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задание?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('daily_tasks').doc(id).delete();
      AuditLogger.log(action: 'delete', collection: 'daily_tasks', docId: id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ежедневные задания'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEditTask(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('daily_tasks').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Ошибка: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Нет заданий'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final id = docs[index].id;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(data['description'] ?? ''),
                  subtitle: Text(
                    'Тип: ${data['type']} | Награда: ${data['reward']} монет | Цель: ${data['target']}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _addOrEditTask(taskId: id, existing: data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteTask(id),
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