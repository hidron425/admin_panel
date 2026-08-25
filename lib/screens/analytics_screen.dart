import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:csv/csv.dart';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:admin_panel/utils/app_state.dart';   // 🆕 глобальное состояние

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 6));
  DateTime _endDate = DateTime.now();

  Map<String, int> activeUsersByDay = {};
  Map<String, int> completedQuestsByDay = {};
  Map<String, int> bannerClicksByDay = {};
  Map<String, int> shopTransitionsByDay = {};

  bool _isLoading = false;
  String? _selectedMallId; // 🆕 текущий выбранный ТЦ

  @override
  void initState() {
    super.initState();
    _selectedMallId = AppState.selectedMallId.value;
    // Слушаем изменения выбранного ТЦ
    AppState.selectedMallId.addListener(_onMallChanged);
    _loadData();
  }

  @override
  void dispose() {
    AppState.selectedMallId.removeListener(_onMallChanged);
    super.dispose();
  }

  void _onMallChanged() {
    if (_selectedMallId != AppState.selectedMallId.value) {
      setState(() {
        _selectedMallId = AppState.selectedMallId.value;
      });
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final firestore = FirebaseFirestore.instance;

    // Получаем список shopId для выбранного ТЦ, если нужно
    Set<String> shopIds = {};
    if (_selectedMallId != null) {
      final shopsSnap = await firestore
          .collection('shops')
          .where('mallId', isEqualTo: _selectedMallId)
          .get();
      shopIds = shopsSnap.docs.map((doc) => doc.id).toSet();
      if (shopIds.isEmpty) {
        // Если нет магазинов, то и данных нет
        setState(() {
          activeUsersByDay = {};
          completedQuestsByDay = {};
          bannerClicksByDay = {};
          shopTransitionsByDay = {};
          _isLoading = false;
        });
        return;
      }
    }

    // Универсальная функция агрегации
    Future<Map<String, int>> aggregate(
        Query collection, String dateField) async {
      final snap = await collection
          .where(dateField,
              isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
          .where(dateField,
              isLessThanOrEqualTo:
                  Timestamp.fromDate(_endDate.add(const Duration(days: 1))))
          .get();
      final map = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = (data[dateField] as Timestamp?)?.toDate();
        if (ts == null) continue;
        final key = DateFormat('yyyy-MM-dd').format(ts);
        map[key] = (map[key] ?? 0) + 1;
      }
      return map;
    }

    try {
      // Активные пользователи: фильтруем по selectedMallId, если ТЦ выбран
      Query usersQuery = firestore.collection('user_progress');
      if (_selectedMallId != null) {
        usersQuery = usersQuery.where('selectedMallId', isEqualTo: _selectedMallId);
      }
      final activeUsers = await aggregate(usersQuery, 'lastActive');

      // Завершённые квесты и переходы в магазины: sales
      Query salesQuery = firestore.collection('sales');
      if (_selectedMallId != null) {
        salesQuery = salesQuery.where('shopId', whereIn: shopIds.toList());
      }
      final completedQuests = await aggregate(salesQuery, 'timestamp');

      // Клики по баннерам
      Query bannersQuery = firestore.collection('banner_clicks');
      if (_selectedMallId != null) {
        bannersQuery = bannersQuery.where('shopId', whereIn: shopIds.toList());
      }
      final bannerClicks = await aggregate(bannersQuery, 'timestamp');

      // Переходы в магазины = completedQuests (по логике)
      final shopTransitions = completedQuests;

      setState(() {
        activeUsersByDay = activeUsers;
        completedQuestsByDay = completedQuests;
        bannerClicksByDay = bannerClicks;
        shopTransitionsByDay = shopTransitions;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки аналитики: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ---- Экспорт CSV ----
  void _exportCsv() {
    final allDays = <String>{}
      ..addAll(activeUsersByDay.keys)
      ..addAll(completedQuestsByDay.keys)
      ..addAll(bannerClicksByDay.keys)
      ..addAll(shopTransitionsByDay.keys);
    final sortedDays = allDays.toList()..sort();

    final rows = <List<String>>[
      ['Date', 'Active Users', 'Completed Quests', 'Banner Clicks', 'Shop Transitions'],
      for (final day in sortedDays)
        [
          day,
          '${activeUsersByDay[day] ?? 0}',
          '${completedQuestsByDay[day] ?? 0}',
          '${bannerClicksByDay[day] ?? 0}',
          '${shopTransitionsByDay[day] ?? 0}',
        ],
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(csv.codeUnits);
    final blob = html.Blob([bytes], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download',
          'analytics_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Общая аналитика'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportCsv,
            tooltip: 'Экспорт CSV',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Выбор периода
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _startDate,
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() => _startDate = picked);
                              _loadData();
                            }
                          },
                          child: Text(
                              'От: ${DateFormat('dd.MM.yyyy').format(_startDate)}'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _endDate,
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now().add(const Duration(days: 1)),
                            );
                            if (picked != null) {
                              setState(() => _endDate = picked);
                              _loadData();
                            }
                          },
                          child: Text(
                              'До: ${DateFormat('dd.MM.yyyy').format(_endDate)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Карточки метрик за сегодня
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _buildMetricCard(
                        'Активные пользователи',
                        activeUsersByDay[
                                DateFormat('yyyy-MM-dd').format(DateTime.now())] ??
                            0,
                      ),
                      _buildMetricCard(
                        'Завершённые квесты',
                        completedQuestsByDay[
                                DateFormat('yyyy-MM-dd').format(DateTime.now())] ??
                            0,
                      ),
                      _buildMetricCard(
                        'Клики по баннерам',
                        bannerClicksByDay[
                                DateFormat('yyyy-MM-dd').format(DateTime.now())] ??
                            0,
                      ),
                      _buildMetricCard(
                        'Переходы в магазины',
                        shopTransitionsByDay[
                                DateFormat('yyyy-MM-dd').format(DateTime.now())] ??
                            0,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text('Активные пользователи',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 250,
                    child: _buildBarChart(activeUsersByDay),
                  ),
                  const SizedBox(height: 24),
                  Text('Клики по баннерам',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 250,
                    child: _buildBarChart(bannerClicksByDay),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricCard(String title, int value) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value.toString(),
                style:
                    const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart(Map<String, int> data) {
    final entries = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) {
      return const Center(child: Text('Нет данных за выбранный период'));
    }
    final maxY = entries
            .map((e) => e.value)
            .reduce((a, b) => a > b ? a : b)
            .toDouble() +
        1;
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barGroups: entries.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return BarChartGroupData(
            x: idx,
            barRods: [
              BarChartRodData(
                toY: item.value.toDouble(),
                color: Colors.blue,
                width: 22,
              ),
            ],
          );
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < entries.length) {
                  return Text(entries[idx].key.substring(5),
                      style: const TextStyle(fontSize: 10));
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: (maxY / 5).clamp(1, double.infinity),
            ),
          ),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
      ),
    );
  }
}