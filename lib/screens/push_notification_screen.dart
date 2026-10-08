import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:intl/intl.dart';
import 'package:admin_panel/utils/audit.dart';
import 'package:admin_panel/utils/app_state.dart';

class PushNotificationScreen extends StatefulWidget {
  const PushNotificationScreen({super.key});

  @override
  State<PushNotificationScreen> createState() => _PushNotificationScreenState();
}

class _PushNotificationScreenState extends State<PushNotificationScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _templateNameController = TextEditingController();

  String? _selectedCity;
  String? _selectedMall;
  int? _minStepsCompleted;
  int? _activeWithinDays;

  bool _sending = false;
  bool _scheduled = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  List<Map<String, dynamic>> _templates = [];
  bool _templatesLoaded = false;
  List<String> _cities = [];
  List<String> _malls = [];
  bool _loadingFilters = true;

  @override
  void initState() {
    super.initState();
    _selectedMall = AppState.selectedMallId.value;
    AppState.selectedMallId.addListener(_onGlobalMallChanged);
    _loadTemplates();
    _loadFilters();
  }

  @override
  void dispose() {
    AppState.selectedMallId.removeListener(_onGlobalMallChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _templateNameController.dispose();
    super.dispose();
  }

  void _onGlobalMallChanged() {
    if (_selectedMall != AppState.selectedMallId.value) {
      setState(() => _selectedMall = AppState.selectedMallId.value);
    }
  }

  Future<void> _loadFilters() async {
    try {
      final data = await _sb
          .from('user_progress')
          .select('selected_city, selected_mall');
      final cities = <String>{};
      final malls = <String>{};
      for (final row in data as List) {
        final m = Map<String, dynamic>.from(row);
        final c = m['selected_city'] as String?;
        final ml = m['selected_mall'] as String?;
        if (c != null && c.isNotEmpty) cities.add(c);
        if (ml != null && ml.isNotEmpty) malls.add(ml);
      }
      if (mounted) {
        setState(() {
          _cities = cities.toList()..sort();
          _malls = malls.toList()..sort();
          _loadingFilters = false;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadFilters: $e');
      if (mounted) setState(() => _loadingFilters = false);
    }
  }

  Future<void> _loadTemplates() async {
    try {
      final data = await _sb.from('push_templates').select();
      if (mounted) {
        setState(() {
          _templates = (data as List).map((j) => Map<String, dynamic>.from(j)).toList();
          _templatesLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadTemplates: $e');
      if (mounted) setState(() => _templatesLoaded = true);
    }
  }

  Future<void> _saveTemplate() async {
    final name = _templateNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название шаблона')));
      return;
    }
    try {
      await _sb.from('push_templates').insert({
        'name': name,
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
      });
      _templateNameController.clear();
      await _loadTemplates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Шаблон сохранён')));
      }
    } catch (e) {
      debugPrint('❌ _saveTemplate: $e');
    }
  }

  void _applyTemplate(Map<String, dynamic> template) {
    _titleController.text = template['title'] ?? '';
    _bodyController.text = template['body'] ?? '';
    setState(() {});
  }

  Future<void> _sendPush() async {
    if (_titleController.text.trim().isEmpty || _bodyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите заголовок и текст')));
      return;
    }

    DateTime? sendAt;
    if (_scheduled && _scheduledDate != null && _scheduledTime != null) {
      sendAt = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        _scheduledTime!.hour,
        _scheduledTime!.minute,
      );
      if (sendAt.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дата отправки должна быть в будущем')));
        return;
      }
    }

    setState(() => _sending = true);
    try {
      // Записываем в очередь push_queue. Реальная отправка — через Cloud Function / воркер.
      await _sb.from('push_queue').insert({
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'priority': 1,
        'urgent': false,
        'status': 'pending',
        'firestore_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'created_at': DateTime.now().toIso8601String(),
      });

      AuditLogger.log(
        action: _scheduled ? 'schedule_push' : 'send_push',
        collection: 'push_queue',
        docId: 'segment',
        changes: {
          'city': _selectedCity,
          'mall': _selectedMall,
          'title': _titleController.text.trim(),
          'body': _bodyController.text.trim(),
          'scheduledAt': sendAt?.toIso8601String(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_scheduled ? 'Уведомление запланировано' : 'Уведомление добавлено в очередь')),
        );
        _titleController.clear();
        _bodyController.clear();
        setState(() {
          _scheduled = false;
          _scheduledDate = null;
          _scheduledTime = null;
        });
      }
    } catch (e) {
      debugPrint('❌ _sendPush: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? const TimeOfDay(hour: 12, minute: 0),
    );
    if (picked != null) setState(() => _scheduledTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedMall == null
            ? 'Push-уведомления (Все ТЦ)'
            : 'Push-уведомления (${_selectedMall})'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Сегментация получателей', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_loadingFilters)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                children: [
                  DropdownButtonFormField<String?>(
                    value: _selectedCity,
                    decoration: const InputDecoration(labelText: 'Город', border: OutlineInputBorder()),
                    items: [null, ..._cities]
                        .map((c) => DropdownMenuItem(value: c, child: Text(c ?? 'Все города')))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCity = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: _selectedMall,
                    decoration: const InputDecoration(labelText: 'Торговый центр', border: OutlineInputBorder()),
                    items: [null, ..._malls]
                        .map((m) => DropdownMenuItem(value: m, child: Text(m ?? 'Все ТЦ')))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedMall = v),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _minStepsCompleted?.toString(),
              decoration: const InputDecoration(labelText: 'Минимум завершённых шагов', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              onChanged: (v) => setState(() => _minStepsCompleted = int.tryParse(v)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _activeWithinDays?.toString(),
              decoration: const InputDecoration(labelText: 'Активен за последние (дней)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              onChanged: (v) => setState(() => _activeWithinDays = int.tryParse(v)),
            ),
            const Divider(height: 32),
            const Text('Сообщение', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Заголовок', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(labelText: 'Текст', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Отложенная отправка'),
                    value: _scheduled,
                    onChanged: (v) => setState(() => _scheduled = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            if (_scheduled) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickDate,
                      child: Text(_scheduledDate != null
                          ? DateFormat('dd.MM.yyyy').format(_scheduledDate!)
                          : 'Выбрать дату'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickTime,
                      child: Text(_scheduledTime != null
                          ? _scheduledTime!.format(context)
                          : 'Выбрать время'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _sendPush,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_scheduled ? 'Запланировать' : 'Отправить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7BFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                ),
              ),
            ),
            const Divider(height: 32),
            Row(
              children: [
                const Expanded(
                  child: Text('Шаблоны', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: 'Сохранить текущий текст как шаблон',
                  onPressed: _saveTemplate,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_templatesLoaded)
              const Center(child: CircularProgressIndicator())
            else if (_templates.isEmpty)
              const Text('Нет сохранённых шаблонов')
            else
              ..._templates.map((t) {
                return Card(
                  child: ListTile(
                    title: Text(t['name'] ?? 'Без названия'),
                    subtitle: Text(t['title'] ?? ''),
                    trailing: TextButton(
                      onPressed: () => _applyTemplate(t),
                      child: const Text('Использовать'),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}