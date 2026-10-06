import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:intl/intl.dart';
import 'package:admin_panel/utils/app_state.dart';

class ExtendedAnalyticsScreen extends StatefulWidget {
  const ExtendedAnalyticsScreen({super.key});

  @override
  State<ExtendedAnalyticsScreen> createState() => _ExtendedAnalyticsScreenState();
}

class _ExtendedAnalyticsScreenState extends State<ExtendedAnalyticsScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  int? _selectedHour;
  String? _selectedMallId;

  List<Map<String, dynamic>> _shopStats = [];
  bool _loading = true;
  Map<String, int> _heatData = {};
  Map<String, Map<String, dynamic>> _shopsInfo = {};

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
    setState(() => _loading = true);
    try {
      // 1. Загружаем магазины
      var shopsQuery = _sb
          .from('shops')
          .select('firestore_id, name, category, map_x, map_y');
      if (_selectedMallId != null) {
        shopsQuery = shopsQuery.eq('mall_id', _selectedMallId!);
      }
      final shopsData = await shopsQuery;

      final shopsMap = <String, Map<String, dynamic>>{};
      for (final row in shopsData as List) {
        final m = Map<String, dynamic>.from(row);
        final id = m['firestore_id'] as String;
        shopsMap[id] = m;
      }

      final shopIds = shopsMap.keys.toSet();

      // 2. Продажи за период
      final startIso = _startDate.toIso8601String();
      final endIso = _endDate.add(const Duration(days: 1)).toIso8601String();

      var salesQuery = _sb
    .from('sales')
    .select('shop_id, timestamp, created_at')
    .gte('created_at', startIso)
    .lte('created_at', endIso);

      if (_selectedMallId != null && shopIds.isNotEmpty) {
        salesQuery = salesQuery.inFilter('shop_id', shopIds.toList());
      }

      final salesData = await salesQuery;

      final Map<String, int> salesCount = {};

      for (final row in salesData as List) {
        final m = Map<String, dynamic>.from(row);
        final shopId = m['shop_id'] as String? ?? '';
        if (shopId.isEmpty) continue;

        final tsRaw = m['created_at']?.toString() ?? m['timestamp']?.toString();
        if (tsRaw == null) continue;
        final ts = DateTime.tryParse(tsRaw);
        if (ts == null) continue;

        if (_selectedHour != null && ts.toLocal().hour != _selectedHour) continue;

        salesCount[shopId] = (salesCount[shopId] ?? 0) + 1;
        
      }

      // 3. Формируем список для таблицы
      final List<Map<String, dynamic>> stats = [];
for (final shopId in shopsMap.keys) {
  final shop = shopsMap[shopId]!;
  final count = salesCount[shopId] ?? 0;
  stats.add({
    'id': shopId,
    'name': shop['name'] ?? shopId,
    'category': shop['category'] ?? '-',
    'count': count,
  });
}
      stats.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      if (mounted) {
        setState(() {
          _shopsInfo = shopsMap;
          _heatData = salesCount;
          _shopStats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadData (extended analytics): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedMallId == null
            ? 'Расширенная аналитика (Все ТЦ)'
            : 'Расширенная аналитика (${_selectedMallId})'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _loading
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Час суток: '),
                      DropdownButton<int?>(
                        value: _selectedHour,
                        hint: const Text('Все часы'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Все часы'),
                          ),
                          ...List.generate(24, (hour) {
                            return DropdownMenuItem<int?>(
                              value: hour,
                              child: Text('$hour:00'),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedHour = val);
                          _loadData();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (_shopsInfo.isNotEmpty) ...[
                    const Text('Тепловая карта посещений',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 300,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const double imageWidth = 2045;
                          const double imageHeight = 731;
                          final double scale = math.min(
                            constraints.maxWidth / imageWidth,
                            constraints.maxHeight / imageHeight,
                          );
                          final double displayWidth = imageWidth * scale;
                          final double displayHeight = imageHeight * scale;
                          final double offsetX = (constraints.maxWidth - displayWidth) / 2;
                          final double offsetY = (constraints.maxHeight - displayHeight) / 2;

                          return Stack(
                            children: [
                              Positioned(
                                left: offsetX,
                                top: offsetY,
                                width: displayWidth,
                                height: displayHeight,
                                child: Container(color: Colors.grey[200]),
                              ),
                              for (final shopId in _shopsInfo.keys)
                                if (_shopsInfo[shopId]!['map_x'] != null &&
                                    _shopsInfo[shopId]!['map_y'] != null &&
                                    _heatData.containsKey(shopId))
                                  Positioned(
                                    left: (_shopsInfo[shopId]!['map_x'] as num) *
                                            imageWidth *
                                            scale +
                                        offsetX -
                                        20,
                                    top: (_shopsInfo[shopId]!['map_y'] as num) *
                                            imageHeight *
                                            scale +
                                        offsetY -
                                        20,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _getHeatColor(_heatData[shopId]!),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${_heatData[shopId]}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  const Text('Сравнение магазинов',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Магазин')),
                        DataColumn(label: Text('Категория')),
                        DataColumn(label: Text('Активаций')),
                      ],
                      rows: _shopStats.map((shop) {
                        return DataRow(cells: [
                          DataCell(Text(shop['name'])),
                          DataCell(Text(shop['category'])),
                          DataCell(Text(shop['count'].toString())),
                        ]);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Color _getHeatColor(int count) {
    final double ratio = (count / 10).clamp(0.0, 1.0);
    return Color.lerp(Colors.green, Colors.red, ratio)!.withOpacity(0.6);
  }
}