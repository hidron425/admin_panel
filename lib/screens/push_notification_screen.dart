import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:admin_panel/utils/audit.dart';

class PushNotificationScreen extends StatefulWidget {
  const PushNotificationScreen({super.key});

  @override
  State<PushNotificationScreen> createState() => _PushNotificationScreenState();
}

class _PushNotificationScreenState extends State<PushNotificationScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _templateNameController = TextEditingController();

  // Сегментация
  String? _selectedCity;
  String? _selectedMall;
  int? _minStepsCompleted; // минимальное количество завершённых шагов
  int? _activeWithinDays;  // активен за последние N дней

  bool _sending = false;
  bool _scheduled = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  // Шаблоны
  List<Map<String, dynamic>> _templates = [];
  bool _templatesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _templateNameController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final snap = await _firestore.collection('push_templates').get();
    setState(() {
      _templates = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
      _templatesLoaded = true;
    });
  }

  Future<void> _saveTemplate() async {
    final name = _templateNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название шаблона')));
      return;
    }
    await _firestore.collection('push_templates').add({
      'name': name,
      'title': _titleController.text.trim(),
      'body': _bodyController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    _templateNameController.clear();
    await _loadTemplates();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Шаблон сохранён')));
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

    // Проверяем отложенную отправку
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
      final segment = {
        'city': _selectedCity,
        'mall': _selectedMall,
        'minStepsCompleted': _minStepsCompleted,
        'activeWithinDays': _activeWithinDays,
      };
      final message = {
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
      };

      final callable = _functions.httpsCallable('sendPushToSegment');
      final result = await callable.call({
        'segment': segment,
        'message': message,
        'scheduledAt': sendAt?.toIso8601String(),
      });

      if (result.data['success'] == true) {
        // Аудит
        AuditLogger.log(
          action: _scheduled ? 'schedule_push' : 'send_push',
          collection: 'notifications',
          docId: 'segment',
          changes: {'segment': segment, 'message': message, 'scheduledAt': sendAt?.toIso8601String()},
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_scheduled ? 'Уведомление запланировано на ${DateFormat('dd.MM.yyyy HH:mm').format(sendAt!)}' : 'Уведомление отправляется')),
          );
          _titleController.clear();
          _bodyController.clear();
          setState(() {
            _scheduled = false;
            _scheduledDate = null;
            _scheduledTime = null;
          });
        }
      } else {
        throw Exception(result.data['error'] ?? 'Неизвестная ошибка');
      }
    } catch (e) {
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
        title: const Text('Push-уведомления'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- Сегментация -----
            const Text('Сегментация получателей', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            FutureBuilder<QuerySnapshot>(
              future: _firestore.collection('user_progress').get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final cities = snapshot.data!.docs
                    .map((d) => (d.data() as Map<String, dynamic>)['selectedCity'] as String?)
                    .where((c) => c != null && c.isNotEmpty)
                    .toSet()
                    .toList()..sort();
                final malls = snapshot.data!.docs
                    .map((d) => (d.data() as Map<String, dynamic>)['selectedMall'] as String?)
                    .where((m) => m != null && m.isNotEmpty)
                    .toSet()
                    .toList()..sort();

                return Column(
                  children: [
                    DropdownButtonFormField<String?>(
                      value: _selectedCity,
                      decoration: const InputDecoration(labelText: 'Город', border: OutlineInputBorder()),
                      items: [null, ...cities].map((c) => DropdownMenuItem(value: c, child: Text(c ?? 'Все города'))).toList(),
                      onChanged: (v) => setState(() => _selectedCity = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: _selectedMall,
                      decoration: const InputDecoration(labelText: 'Торговый центр', border: OutlineInputBorder()),
                      items: [null, ...malls].map((m) => DropdownMenuItem(value: m, child: Text(m ?? 'Все ТЦ'))).toList(),
                      onChanged: (v) => setState(() => _selectedMall = v),
                    ),
                  ],
                );
              },
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

            // ----- Сообщение -----
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

            // ----- Отправка -----
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
                icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                label: Text(_scheduled ? 'Запланировать' : 'Отправить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                ),
              ),
            ),

            const Divider(height: 32),

            // ----- Шаблоны -----
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
              ...List.generate(_templates.length, (index) {
                final t = _templates[index];
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