import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:admin_panel/utils/audit.dart';   // 🆕 сервис аудита

class StatsScreen extends StatefulWidget {
  final int initialTabIndex;
  const StatsScreen({Key? key, this.initialTabIndex = 0}) : super(key: key);

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _shopId;
  String _period = 'week';
  int _firstSales = 0;
  int _secondarySales = 0;
  int _totalSales = 0;
  List<Map<String, dynamic>> _activations = [];
  List<Map<String, dynamic>> _dailySales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    _getShopId();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _getShopId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.email!).get();
      if (mounted) {
        setState(() {
          _shopId = doc.data()?['storeId'] as String?;
          _loading = false;
        });
      }
      if (_shopId != null) {
        await _loadStats();
        await _loadActivations();
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStats() async {
    if (_shopId == null) return;

    final now = DateTime.now();
    DateTime startDate;
    switch (_period) {
      case 'today':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'week':
        startDate = now.subtract(const Duration(days: 7));
        break;
      case 'month':
        startDate = DateTime(now.year, now.month - 1, now.day);
        break;
      default:
        startDate = DateTime(now.year, now.month, now.day);
    }

    final salesQuery = await FirebaseFirestore.instance
        .collection('sales')
        .where('shopId', isEqualTo: _shopId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .get();

    int first = 0;
    int secondary = 0;
    Map<String, int> dailyCount = {};

    for (var doc in salesQuery.docs) {
      final step = doc['step'] as int? ?? 0;
      final ts = (doc['timestamp'] as Timestamp).toDate();
      final day = DateFormat('yyyy-MM-dd').format(ts);
      dailyCount[day] = (dailyCount[day] ?? 0) + 1;

      if (step == 1) first++;
      else if (step >= 2) secondary++;
    }

    final sortedDays = dailyCount.keys.toList()..sort();
    final dailySales = sortedDays.map((day) => {
      'day': day,
      'count': dailyCount[day] ?? 0,
    }).toList();

    if (mounted) {
      setState(() {
        _firstSales = first;
        _secondarySales = secondary;
        _totalSales = first + secondary;
        _dailySales = dailySales;
      });
    }
  }

  Future<void> _loadActivations() async {
    if (_shopId == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('sales')
        .where('shopId', isEqualTo: _shopId)
        .orderBy('timestamp', descending: true)
        .get();

    final List<Map<String, dynamic>> list = [];
    for (var doc in snapshot.docs) {
      final step = doc['step'] as int? ?? 0;
      list.add({
        'id': doc.id,
        'timestamp': (doc['timestamp'] as Timestamp).toDate(),
        'step': step,
        'type': step == 1 ? 'Первая' : 'Вторичная',
        'userId': doc['userId'] ?? 'аноним',
      });
    }
    if (mounted) {
      setState(() {
        _activations = list;
      });
    }
  }

  Future<void> _exportToCsv() async {
    if (_activations.isEmpty) return;

    List<List<dynamic>> rows = [
      ['Дата', 'Шаг', 'Тип', 'ID пользователя']
    ];
    for (var act in _activations) {
      rows.add([
        DateFormat('yyyy-MM-dd HH:mm:ss').format(act['timestamp']),
        act['step'],
        act['type'],
        act['userId'],
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(csv.codeUnits);
    final blob = html.Blob([bytes], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'activations.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_shopId == null) {
      return const Scaffold(body: Center(child: Text('Не удалось определить магазин')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика и уведомления'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '📊 Статистика'),
            Tab(text: '📋 История'),
            Tab(text: '📢 Уведомления'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStatsTab(),
          _buildHistoryTab(),
          const NotificationsForm(),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
    if (_dailySales.isEmpty && _totalSales == 0) {
      return const Center(child: Text('Нет данных'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Период: '),
              DropdownButton<String>(
                value: _period,
                items: const [
                  DropdownMenuItem(value: 'today', child: Text('Сегодня')),
                  DropdownMenuItem(value: 'week', child: Text('Неделя')),
                  DropdownMenuItem(value: 'month', child: Text('Месяц')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _period = value);
                    _loadStats();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Первые продажи (начало пути)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('$_firstSales', style: const TextStyle(fontSize: 24)),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Вторичные продажи (2+ шаг)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('$_secondarySales', style: const TextStyle(fontSize: 24)),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Всего продаж', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('$_totalSales', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('График активности (продажи по дням)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _dailySales.isEmpty
              ? const Text('Нет данных')
              : SizedBox(
                  height: 250,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (_dailySales.map((e) => e['count'] as int).reduce((a,b) => a > b ? a : b).toDouble() + 1).clamp(1, double.infinity),
                      barGroups: _dailySales.asMap().entries.map((entry) {
                        int idx = entry.key;
                        var data = entry.value;
                        return BarChartGroupData(
                          x: idx,
                          barRods: [
                            BarChartRodData(
                              toY: (data['count'] as int).toDouble(),
                              color: Theme.of(context).primaryColor,
                              width: 30,
                            ),
                          ],
                        );
                      }).toList(),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < _dailySales.length) {
                                return Text(_dailySales[idx]['day'], style: const TextStyle(fontSize: 10));
                              }
                              return const Text('');
                            },
                            reservedSize: 40,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: true),
                      borderData: FlBorderData(show: true),
                    ),
                  ),
                ),
          // Добавляем статистику коллабораций
          FutureBuilder<int>(
            future: _getCollabClicks(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return Card(
                margin: const EdgeInsets.only(top: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Переходы по коллаборациям', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('${snapshot.data}', style: const TextStyle(fontSize: 24)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<int> _getCollabClicks() async {
    if (_shopId == null) return 0;
    final snapshot = await FirebaseFirestore.instance
        .collection('active_collabs')
        .where('fromShopId', isEqualTo: _shopId)
        .get();
    int total = 0;
    for (var doc in snapshot.docs) {
      total += (doc.data()['clicks'] as int? ?? 0);
    }
    return total;
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        if (_activations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Экспорт в CSV'),
              onPressed: _exportToCsv,
            ),
          ),
        Expanded(
          child: _activations.isEmpty
              ? const Center(child: Text('Нет активаций'))
              : ListView.builder(
                  itemCount: _activations.length,
                  itemBuilder: (context, index) {
                    final act = _activations[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text('Шаг ${act['step']} — ${act['type']}'),
                        subtitle: Text(DateFormat('dd.MM.yyyy HH:mm:ss').format(act['timestamp'])),
                        trailing: Text(act['userId'].toString().substring(0, 6) + '...'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class NotificationsForm extends StatefulWidget {
  const NotificationsForm({Key? key}) : super(key: key);

  @override
  State<NotificationsForm> createState() => _NotificationsFormState();
}

class _NotificationsFormState extends State<NotificationsForm> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _priorityController = TextEditingController(text: '1');
  bool _urgent = false;
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  bool _sending = false;
  String? _shopId;
  int _subscribersCount = 0;

  @override
  void initState() {
    super.initState();
    _getShopIdAndSubscribers();
  }

  Future<void> _getShopIdAndSubscribers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      final userDoc = await _firestore.collection('users').doc(user.email!).get();
      final shopId = userDoc.data()?['storeId'] as String?;
      if (shopId != null) {
        setState(() => _shopId = shopId);
        final snapshot = await _firestore
            .collection('user_progress')
            .where('subscribedShops', arrayContains: shopId)
            .get();
        setState(() => _subscribersCount = snapshot.docs.length);
      }
    }
  }

  Future<void> _sendNotification() async {
    if (_titleController.text.trim().isEmpty || _bodyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заполните заголовок и текст')));
      return;
    }
    if (_shopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Магазин не определён')));
      return;
    }
    if (_subscribersCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет подписчиков для рассылки')));
      return;
    }

    setState(() => _sending = true);
    try {
      final snapshot = await _firestore
          .collection('user_progress')
          .where('subscribedShops', arrayContains: _shopId)
          .get();
      final userIds = snapshot.docs.map((doc) => doc.id).toList();

      final callable = _functions.httpsCallable('addPushToQueue');
      final result = await callable.call({
        'shopId': _shopId,
        'userIds': userIds,
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'priority': int.tryParse(_priorityController.text) ?? 1,
        'urgent': _urgent,
      });

      if (result.data['success'] == true) {
        // 🆕 Аудит отправки push-уведомления
        AuditLogger.log(
          action: 'send_push',
          collection: 'user_progress',
          docId: _shopId!,  // идентификатор магазина
          changes: {
            'title': _titleController.text.trim(),
            'body': _bodyController.text.trim(),
            'subscribersCount': userIds.length,
          },
        );
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Уведомление поставлено в очередь для ${result.data['count']} подписчиков'),
        ));
        _titleController.clear();
        _bodyController.clear();
        _priorityController.text = '1';
        setState(() => _urgent = false);
      } else {
        throw Exception('Функция вернула ошибку');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Подписчиков вашего магазина: $_subscribersCount', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Заголовок уведомления'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyController,
            decoration: const InputDecoration(labelText: 'Текст уведомления'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _priorityController,
            decoration: const InputDecoration(labelText: 'Приоритет (1-10)'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Срочное уведомление (пропустит очередь)'),
            value: _urgent,
            onChanged: (val) => setState(() => _urgent = val),
          ),
          const SizedBox(height: 32),
          Center(
            child: ElevatedButton(
              onPressed: _sending ? null : _sendNotification,
              child: _sending ? const CircularProgressIndicator() : const Text('Отправить push'),
            ),
          ),
        ],
      ),
    );
  }
}