import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:admin_panel/utils/audit.dart';
import 'package:admin_panel/utils/app_state.dart';

class DailyTasksManagerScreen extends StatefulWidget {
  const DailyTasksManagerScreen({super.key});

  @override
  State<DailyTasksManagerScreen> createState() => _DailyTasksManagerScreenState();
}

class _DailyTasksManagerScreenState extends State<DailyTasksManagerScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  String? _selectedMallId;
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedMallId = AppState.selectedMallId.value;
    AppState.selectedMallId.addListener(_onMallChanged);
    _loadTasks();
  }

  @override
  void dispose() {
    AppState.selectedMallId.removeListener(_onMallChanged);
    super.dispose();
  }

  void _onMallChanged() {
    if (_selectedMallId != AppState.selectedMallId.value) {
      setState(() => _selectedMallId = AppState.selectedMallId.value);
      _loadTasks();
    }
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      var query = _sb.from('daily_tasks').select();
      if (_selectedMallId != null) {
        query = query.eq('mall_id', _selectedMallId!);
      }
      final data = await query.order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _tasks = (data as List).map((j) => Map<String, dynamic>.from(j)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadTasks: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addOrEditTask({String? taskId, Map<String, dynamic>? existing}) async {
    final isEdit = taskId != null;
    final formKey = GlobalKey<FormState>();

    String selectedType = existing?['type'] ?? 'complete_quest';
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final rewardCtrl = TextEditingController(text: existing?['reward']?.toString() ?? '50');
    final targetCtrl = TextEditingController(text: existing?['target']?.toString() ?? '1');
    String? category = existing?['category'] as String?;

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
                    items: const [
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
                final data = <String, dynamic>{
                  'type': selectedType,
                  'description': descCtrl.text.trim(),
                  'reward': int.tryParse(rewardCtrl.text) ?? 50,
                  'target': int.tryParse(targetCtrl.text) ?? 1,
                  'category': selectedType == 'visit_category' ? category : null,
                  'active': true,
                  'mall_id': _selectedMallId,
                };
                try {
                  if (isEdit) {
                    await _sb.from('daily_tasks').update(data).eq('id', taskId);
                    AuditLogger.log(action: 'update', collection: 'daily_tasks', docId: taskId, changes: data);
                  } else {
                    data['created_at'] = DateTime.now().toIso8601String();
                    final result = await _sb.from('daily_tasks').insert(data).select('id').single();
                    AuditLogger.log(action: 'create', collection: 'daily_tasks', docId: result['id'].toString(), changes: data);
                  }
                  if (mounted) Navigator.pop(ctx);
                  _loadTasks();
                } catch (e) {
                  debugPrint('❌ save task: $e');
                }
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
      try {
        await _sb.from('daily_tasks').delete().eq('id', id);
        AuditLogger.log(action: 'delete', collection: 'daily_tasks', docId: id);
        _loadTasks();
      } catch (e) {
        debugPrint('❌ delete task: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedMallId == null
            ? 'Ежедневные задания (Все ТЦ)'
            : 'Ежедневные задания (${_selectedMallId})'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _addOrEditTask()),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? const Center(child: Text('Нет заданий'))
              : ListView.builder(
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) {
                    final data = _tasks[index];
                    final id = data['id'].toString();
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
                ),
    );
  }
}