import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:admin_panel/utils/audit.dart';   // 🆕 сервис аудита

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({Key? key}) : super(key: key);

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  final _firestore = FirebaseFirestore.instance;
  String? _shopId;
  List<Map<String, dynamic>> _promotions = [];
  bool _loading = true;

  DateTime _displayMonth = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _getShopId();
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Future<void> _getShopId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      final doc = await _firestore.collection('users').doc(user.email!).get();
      if (mounted) {
        setState(() {
          _shopId = doc.data()?['storeId'] as String?;
        });
      }
      if (_shopId != null) {
        await _loadPromotions();
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPromotions() async {
    if (_shopId == null) return;
    final snapshot = await _firestore
        .collection('store_promotions')
        .where('shopId', isEqualTo: _shopId)
        .get();

    final List<Map<String, dynamic>> list = [];
    final Map<DateTime, List<Map<String, dynamic>>> events = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final startDate = (data['startDate'] as Timestamp).toDate();
      final endDate = (data['endDate'] as Timestamp).toDate();

      final item = {
        'id': doc.id,
        'title': data['title'] ?? '',
        'description': data['description'] ?? '',
        'discount': data['discount'] ?? '',
        'startDate': startDate,
        'endDate': endDate,
        'isActive': data['isActive'] ?? false,
      };
      list.add(item);

      DateTime day = DateTime(startDate.year, startDate.month, startDate.day);
      final endDay = DateTime(endDate.year, endDate.month, endDate.day);
      while (day.isBefore(endDay) || day.isAtSameMomentAs(endDay)) {
        final dateKey = DateTime(day.year, day.month, day.day);
        events.putIfAbsent(dateKey, () => []).add(item);
        day = day.add(const Duration(days: 1));
      }
    }

    if (mounted) {
      setState(() {
        _promotions = list;
        _events = events;
      });
    }
  }

  Future<void> _addOrEditPromotion([Map<String, dynamic>? existing]) async {
    final isEdit = existing != null;
    final titleCtrl = TextEditingController(text: existing?['title']);
    final descCtrl = TextEditingController(text: existing?['description']);
    final discountCtrl = TextEditingController(text: existing?['discount']);
    DateTime startDate = existing != null ? existing['startDate'] : DateTime.now();
    DateTime endDate = existing != null ? existing['endDate'] : DateTime.now().add(const Duration(days: 7));
    bool isActive = existing?['isActive'] ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(isEdit ? 'Редактировать акцию' : 'Новая акция'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Название акции')),
                  const SizedBox(height: 8),
                  TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание'), maxLines: 2),
                  const SizedBox(height: 8),
                  TextField(controller: discountCtrl, decoration: const InputDecoration(labelText: 'Скидка (например -20%)')),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Дата начала'),
                    subtitle: Text(_formatDate(startDate)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setStateDialog(() => startDate = picked);
                    },
                  ),
                  ListTile(
                    title: const Text('Дата окончания'),
                    subtitle: Text(_formatDate(endDate)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate,
                        firstDate: startDate,
                        lastDate: startDate.add(const Duration(days: 365)),
                      );
                      if (picked != null) setStateDialog(() => endDate = picked);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Активно'),
                    value: isActive,
                    onChanged: (val) => setStateDialog(() => isActive = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty) return;
                  final data = {
                    'shopId': _shopId,
                    'title': titleCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'discount': discountCtrl.text.trim(),
                    'startDate': Timestamp.fromDate(startDate),
                    'endDate': Timestamp.fromDate(endDate),
                    'isActive': isActive,
                  };
                  String action;
                  String docId;
                  if (isEdit) {
                    await _firestore.collection('store_promotions').doc(existing['id']).update(data);
                    action = 'update';
                    docId = existing['id'];
                  } else {
                    final docRef = await _firestore.collection('store_promotions').add(data);
                    action = 'create';
                    docId = docRef.id;
                  }
                  // 🆕 Аудит создания/обновления акции
                  AuditLogger.log(
                    action: action,
                    collection: 'store_promotions',
                    docId: docId,
                    changes: data,
                  );
                  if (mounted) Navigator.pop(context);
                  await _loadPromotions();
                },
                child: Text(isEdit ? 'Сохранить' : 'Добавить'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deletePromotion(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить акцию?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('store_promotions').doc(id).delete();
      // 🆕 Аудит удаления
      AuditLogger.log(
        action: 'delete',
        collection: 'store_promotions',
        docId: id,
      );
      await _loadPromotions();
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _events[key] ?? [];
  }

  Widget _buildTinyCalendar() {
    final firstDayOfMonth = DateTime(_displayMonth.year, _displayMonth.month, 1);
    final lastDayOfMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    int startWeekday = firstDayOfMonth.weekday;
    int offset = startWeekday - 1;

    List<DateTime> days = [];
    for (int i = offset; i > 0; i--) {
      days.add(firstDayOfMonth.subtract(Duration(days: i)));
    }
    for (int i = 1; i <= daysInMonth; i++) {
      days.add(DateTime(_displayMonth.year, _displayMonth.month, i));
    }
    int remaining = 42 - days.length;
    for (int i = 1; i <= remaining; i++) {
      days.add(lastDayOfMonth.add(Duration(days: i)));
    }

    final weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return Container(
      margin: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: weekdays.map((d) => Expanded(child: Text(d, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))).toList(),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: GridView.count(
              crossAxisCount: 7,
              childAspectRatio: 3.0,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: days.map((day) {
                final isCurrentMonth = day.month == _displayMonth.month;
                final events = _getEventsForDay(day);
                final isSelected = _selectedDay != null &&
                    day.year == _selectedDay!.year &&
                    day.month == _selectedDay!.month &&
                    day.day == _selectedDay!.day;

                Color? bgColor;
                if (events.isNotEmpty) {
                  final now = DateTime.now();
                  final hasActive = events.any((e) => e['startDate'].isBefore(now) && e['endDate'].isAfter(now));
                  final hasFuture = events.any((e) => e['startDate'].isAfter(now));
                  if (hasActive) bgColor = Colors.green.shade100;
                  else if (hasFuture) bgColor = Colors.orange.shade100;
                  else bgColor = Colors.grey.shade300;
                }

                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = day),
                  child: Container(
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: bgColor ?? (isSelected ? Theme.of(context).primaryColor.withOpacity(0.3) : Colors.transparent),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isCurrentMonth ? Colors.black : Colors.grey,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (_shopId == null || _loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedEvents = _selectedDay != null ? _getEventsForDay(_selectedDay!) : [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Календарь акций'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addOrEditPromotion),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(onPressed: () => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1, 1)), icon: const Icon(Icons.chevron_left)),
                  Text(
                    '${_monthName(_displayMonth.month)} ${_displayMonth.year}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(onPressed: () => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 1)), icon: const Icon(Icons.chevron_right)),
                ],
              ),
            ),
            _buildTinyCalendar(),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _selectedDay != null ? 'Акции на ${_formatDate(_selectedDay!)}' : 'Выберите дату',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            selectedEvents.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('Нет акций на этот день')),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: selectedEvents.length,
                    itemBuilder: (context, index) {
                      final promo = selectedEvents[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          title: Text(promo['title']),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${promo['discount']} — ${promo['description']}'),
                              Text(
                                '${_formatDate(promo['startDate'])} – ${_formatDate(promo['endDate'])}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit), onPressed: () => _addOrEditPromotion(promo)),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deletePromotion(promo['id'])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}