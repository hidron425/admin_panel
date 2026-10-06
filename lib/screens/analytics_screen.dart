import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:fl_chart/fl_chart.dart';
import 'package:csv/csv.dart';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:admin_panel/utils/app_state.dart';

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
  String? _selectedMallId;

  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _selectedMallId = AppState.selectedMallId.value;
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
      setState(() => _selectedMallId = AppState.selectedMallId.value);
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Если выбран ТЦ — получаем список его магазинов
      Set<String> shopIds = {};
      if (_selectedMallId != null) {
        final shopsData = await _sb
            .from('shops')
            .select('firestore_id')
            .eq('mall_id', _selectedMallId!);
        shopIds = (shopsData as List)
            .map((json) => json['firestore_id'] as String)
            .toSet();

        if (shopIds.isEmpty) {
          if (mounted) {
            setState(() {
              activeUsersByDay = {};
              completedQuestsByDay = {};
              bannerClicksByDay = {};
              shopTransitionsByDay = {};
              _isLoading = false;
            });
          }
          return;
        }
      }

      final startIso = _startDate.toIso8601String();
      final endIso = _endDate.add(const Duration(days: 1)).toIso8601String();

      // Универсальная агрегация
      Future<Map<String, int>> aggregate({
        required String table,
        required String dateField,
        String? filterField,
        List<String>? filterValues,
      }) async {
        var query = _sb
            .from(table)
            .select('$dateField')
            .gte(dateField, startIso)
            .lte(dateField, endIso);

        if (filterField != null && filterValues != null && filterValues.isNotEmpty) {
          query = query.inFilter(filterField, filterValues);
        }

        final data = await query;
        final map = <String, int>{};
        for (final row in data as List) {
          final raw = row[dateField];
          if (raw == null) continue;
          final ts = DateTime.tryParse(raw.toString());
          if (ts == null) continue;
          final key = DateFormat('yyyy-MM-dd').format(ts);
          map[key] = (map[key] ?? 0) + 1;
        }
        return map;
      }

      // 1. Активные пользователи
      final activeUsers = await aggregate(
        table: 'user_progress',
        dateField: 'last_active',
        filterField: _selectedMallId != null ? 'selected_mall_id' : null,
        filterValues: _selectedMallId != null ? [_selectedMallId!] : null,
      );

      // 2. Завершённые квесты / переходы (sales)
      final completedQuests = await aggregate(
        table: 'sales',
        dateField: 'created_at',
        filterField: _selectedMallId != null ? 'shop_id' : null,
        filterValues: _selectedMallId != null ? shopIds.toList() : null,
      );

      // 3. Клики по баннерам
      final bannerClicks = await aggregate(
        table: 'banner_clicks',
        dateField: 'created_at',
        filterField: _selectedMallId != null ? 'shop_id' : null,
        filterValues: _selectedMallId != null ? shopIds.toList() : null,
      );

      if (mounted) {
        setState(() {
          activeUsersByDay = activeUsers;
          completedQuestsByDay = completedQuests;
          bannerClicksByDay = bannerClicks;
          shopTransitionsByDay = completedQuests;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки аналитики: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
      ..setAttribute(
          'download', 'analytics_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

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
                          child: Text('От: ${DateFormat('dd.MM.yyyy').format(_startDate)}'),
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
                          child: Text('До: ${DateFormat('dd.MM.yyyy').format(_endDate)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _buildMetricCard(
                        'Активные пользователи',
                        activeUsersByDay[
                                DateFormat('yyyy-MM-dd').format(DateTime.now())] ?? 0,
                      ),
                      _buildMetricCard(
                        'Завершённые квесты',
                        completedQuestsByDay[
                                DateFormat('yyyy-MM-dd').format(DateTime.now())] ?? 0,
                      ),
                      _buildMetricCard(
                        'Клики по баннерам',
                        bannerClicksByDay[
                                DateFormat('yyyy-MM-dd').format(DateTime.now())] ?? 0,
                      ),
                      _buildMetricCard(
                        'Переходы в магазины',
                        shopTransitionsByDay[
                                DateFormat('yyyy-MM-dd').format(DateTime.now())] ?? 0,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text('Активные пользователи', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(height: 250, child: _buildBarChart(activeUsersByDay)),
                  const SizedBox(height: 24),
                  Text('Клики по баннерам', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(height: 250, child: _buildBarChart(bannerClicksByDay)),
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
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart(Map<String, int> data) {
    final entries = data.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) {
      return const Center(child: Text('Нет данных за выбранный период'));
    }
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble() + 1;
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
              BarChartRodData(toY: item.value.toDouble(), color: Colors.blue, width: 22),
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