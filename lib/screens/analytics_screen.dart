import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:csv/csv.dart';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final firestore = FirebaseFirestore.instance;

    // Готовим список дней для осей графика
    final days = <String>[];
    for (var d = _startDate;
        d.isBefore(_endDate) || d.isAtSameMomentAs(_endDate);
        d = d.add(const Duration(days: 1))) {
      days.add(DateFormat('yyyy-MM-dd').format(d));
    }

    // Универсальная функция агрегации по дням
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
      final activeUsers = await aggregate(
          firestore.collection('user_progress'), 'lastActive');
      // Завершённые квесты – можно считать продажи или специальное поле;
      // здесь используем sales как общее количество шагов (квестов)
      final completedQuests = await aggregate(
          firestore.collection('sales'), 'timestamp');
      final bannerClicks = await aggregate(
          firestore.collection('banner_clicks'), 'timestamp');
      // Переходы в магазины – тоже sales (можно отделить, но пока так)
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
                  // График: активные пользователи по дням
                  Text('Активные пользователи',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 250,
                    child: _buildBarChart(activeUsersByDay),
                  ),
                  const SizedBox(height: 24),
                  // График: клики по баннерам
                  Text('Клики по баннерам',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 250,
                    child: _buildBarChart(bannerClicksByDay),
                  ),
                  // При желании добавьте графики для остальных метрик
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