import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:admin_panel/utils/app_state.dart';

class StatsScreen extends StatefulWidget {
  final int initialTabIndex;
  const StatsScreen({Key? key, this.initialTabIndex = 0}) : super(key: key);

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with SingleTickerProviderStateMixin {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  late TabController _tabController;
  String? _shopId;
  String? _selectedMallId;
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
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
    _selectedMallId = AppState.selectedMallId.value;
    AppState.selectedMallId.addListener(_onMallChanged);
    _getShopId();
  }

  @override
  void dispose() {
    AppState.selectedMallId.removeListener(_onMallChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onMallChanged() {
    if (_selectedMallId != AppState.selectedMallId.value) {
      setState(() => _selectedMallId = AppState.selectedMallId.value);
      if (_shopId == null) {
        _loadStats();
        _loadActivations();
      }
    }
  }

  Future<void> _getShopId() async {
    try {
      final email = _sb.auth.currentUser?.email;
      if (email != null) {
        final data = await _sb
            .from('user_metadata')
            .select('store_id')
            .eq('email', email)
            .maybeSingle();
        if (mounted) {
          setState(() {
            _shopId = data?['store_id'] as String?;
          });
        }
        await _loadStats();
        await _loadActivations();
      }
    } catch (e) {
      debugPrint('❌ _getShopId: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  DateTime _getStartDate() {
    final now = DateTime.now();
    switch (_period) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return DateTime(now.year, now.month - 1, now.day);
      default:
        return DateTime(now.year, now.month, now.day);
    }
  }

  Future<void> _loadStats() async {
    try {
      final startDate = _getStartDate();
      final startIso = startDate.toIso8601String();

      List<String> shopIds = [];
      if (_shopId != null) {
        shopIds = [_shopId!];
      } else {
        var shopsQuery = _sb.from('shops').select('firestore_id');
        if (_selectedMallId != null) {
          shopsQuery = shopsQuery.eq('mall_id', _selectedMallId!);
        }
        final shops = await shopsQuery;
        shopIds = (shops as List).map((j) => j['firestore_id'] as String).toList();
      }

      if (shopIds.isEmpty) {
        if (mounted) {
          setState(() {
            _firstSales = 0;
            _secondarySales = 0;
            _totalSales = 0;
            _dailySales = [];
          });
        }
        return;
      }

      final salesData = await _sb
          .from('sales')
          .select('step, created_at')
          .inFilter('shop_id', shopIds)
          .gte('created_at', startIso);

      int first = 0;
      int secondary = 0;
      final Map<String, int> dailyCount = {};

      for (final row in salesData as List) {
        final m = Map<String, dynamic>.from(row);
        final step = (m['step'] as num?)?.toInt() ?? 0;
        final tsRaw = m['created_at']?.toString();
        if (tsRaw == null) continue;
        final ts = DateTime.tryParse(tsRaw);
        if (ts == null) continue;
        final day = DateFormat('yyyy-MM-dd').format(ts.toLocal());
        dailyCount[day] = (dailyCount[day] ?? 0) + 1;
        if (step == 1) first++;
        else if (step >= 2) secondary++;
      }

      final sortedDays = dailyCount.keys.toList()..sort();
      final dailySales = sortedDays
          .map((day) => {'day': day, 'count': dailyCount[day] ?? 0})
          .toList();

      if (mounted) {
        setState(() {
          _firstSales = first;
          _secondarySales = secondary;
          _totalSales = first + secondary;
          _dailySales = dailySales;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadStats: $e');
    }
  }

  Future<void> _loadActivations() async {
    try {
      List<String> shopIds = [];
      if (_shopId != null) {
        shopIds = [_shopId!];
      } else {
        var shopsQuery = _sb.from('shops').select('firestore_id');
        if (_selectedMallId != null) {
          shopsQuery = shopsQuery.eq('mall_id', _selectedMallId!);
        }
        final shops = await shopsQuery;
        shopIds = (shops as List).map((j) => j['firestore_id'] as String).toList();
      }

      if (shopIds.isEmpty) {
        if (mounted) setState(() => _activations = []);
        return;
      }

      final data = await _sb
          .from('sales')
          .select('firestore_id, user_id, step, created_at')
          .inFilter('shop_id', shopIds)
          .order('created_at', ascending: false)
          .limit(200);

      final list = <Map<String, dynamic>>[];
      for (final row in data as List) {
        final m = Map<String, dynamic>.from(row);
        final step = (m['step'] as num?)?.toInt() ?? 0;
        final ts = DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now();
        list.add({
          'id': m['firestore_id']?.toString() ?? '',
          'timestamp': ts,
          'step': step,
          'type': step == 1 ? 'Первая' : 'Вторичная',
          'userId': m['user_id'] ?? 'аноним',
        });
      }
      if (mounted) setState(() => _activations = list);
    } catch (e) {
      debugPrint('❌ _loadActivations: $e');
    }
  }

  Future<void> _exportToCsv() async {
    if (_activations.isEmpty) return;
    final rows = <List<dynamic>>[
      ['Дата', 'Шаг', 'Тип', 'ID пользователя']
    ];
    for (var act in _activations) {
      rows.add([
        DateFormat('yyyy-MM-dd HH:mm:ss').format(act['timestamp'] as DateTime),
        act['step'],
        act['type'],
        act['userId'],
      ]);
    }
    final csv = const ListToCsvConverter().convert(rows);
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
    if (_shopId == null && _selectedMallId == null) {
      return const Scaffold(body: Center(child: Text('Выберите ТЦ или войдите как магазин')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_shopId != null
            ? 'Статистика магазина'
            : _selectedMallId == null
                ? 'Статистика (Все ТЦ)'
                : 'Статистика (${_selectedMallId})'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '📊 Статистика'),
            Tab(text: '📋 История'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStatsTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
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
          const Text('График активности', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _dailySales.isEmpty
              ? const Text('Нет данных')
              : SizedBox(
                  height: 250,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (_dailySales.map((e) => e['count'] as int).reduce((a, b) => a > b ? a : b).toDouble() + 1).clamp(1, double.infinity),
                      barGroups: _dailySales.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final data = entry.value;
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
                            getTitlesWidget: (value, meta) {
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
        ],
      ),
    );
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
                    final userId = act['userId'].toString();
                    final shortId = userId.length > 6 ? userId.substring(0, 6) : userId;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text('Шаг ${act['step']} — ${act['type']}'),
                        subtitle: Text(DateFormat('dd.MM.yyyy HH:mm:ss').format(act['timestamp'] as DateTime)),
                        trailing: Text('$shortId...'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}