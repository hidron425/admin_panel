import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:admin_panel/utils/audit.dart';
import 'package:admin_panel/utils/app_state.dart';   // 🆕 глобальное состояние

class ExtendedAnalyticsScreen extends StatefulWidget {
  const ExtendedAnalyticsScreen({super.key});

  @override
  State<ExtendedAnalyticsScreen> createState() => _ExtendedAnalyticsScreenState();
}

class _ExtendedAnalyticsScreenState extends State<ExtendedAnalyticsScreen> {
  final _firestore = FirebaseFirestore.instance;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  int? _selectedHour; // null = все часы
  String? _selectedMallId;   // 🆕 текущий выбранный ТЦ

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
      // 1. Загружаем магазины с учётом выбранного ТЦ
      Query shopsQuery = _firestore.collection('shops');
      if (_selectedMallId != null) {
        shopsQuery = shopsQuery.where('mallId', isEqualTo: _selectedMallId);
      }
      final shopsSnap = await shopsQuery.get();
      final shopsMap = <String, Map<String, dynamic>>{};
      for (var doc in shopsSnap.docs) {
        shopsMap[doc.id] = doc.data() as Map<String, dynamic>;
      }

      // Множество ID магазинов выбранного ТЦ (для фильтрации продаж)
      final shopIds = shopsMap.keys.toSet();

      // 2. Получаем продажи за период
      Query salesQuery = _firestore
          .collection('sales')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(_endDate.add(const Duration(days: 1))));

      final salesSnap = await salesQuery.get();
      final Map<String, int> salesCount = {};
      final Map<String, double> salesAmount = {};

      for (var doc in salesSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final shopId = data['shopId'] as String? ?? '';
        if (shopId.isEmpty) continue;
        // Если выбран ТЦ, пропускаем продажи магазинов не из этого ТЦ
        if (_selectedMallId != null && !shopIds.contains(shopId)) continue;

        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        if (ts == null) continue;

        if (_selectedHour != null && ts.hour != _selectedHour) continue;

        salesCount[shopId] = (salesCount[shopId] ?? 0) + 1;
        final amount = (data['amount'] as num?)?.toDouble();
        if (amount != null) {
          salesAmount[shopId] = (salesAmount[shopId] ?? 0) + amount;
        }
      }

      // Формируем список для таблицы
      final List<Map<String, dynamic>> stats = [];
      for (final shopId in shopsMap.keys) {
        final shop = shopsMap[shopId]!;
        final count = salesCount[shopId] ?? 0;
        final totalAmount = salesAmount[shopId] ?? 0.0;
        final avgAmount = count > 0 ? totalAmount / count : 0.0;
        stats.add({
          'id': shopId,
          'name': shop['name'] ?? shopId,
          'category': shop['category'] ?? '-',
          'count': count,
          'totalAmount': totalAmount,
          'avgAmount': avgAmount,
        });
      }
      stats.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      setState(() {
        _shopsInfo = shopsMap;
        _heatData = salesCount;
        _shopStats = stats;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
      setState(() => _loading = false);
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
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
                  // Фильтр по времени суток
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

                  // Тепловая карта
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
                                if (_shopsInfo[shopId]!['mapX'] != null &&
                                    _shopsInfo[shopId]!['mapY'] != null &&
                                    _heatData.containsKey(shopId))
                                  Positioned(
                                    left: _shopsInfo[shopId]!['mapX'] * imageWidth * scale + offsetX - 20,
                                    top: _shopsInfo[shopId]!['mapY'] * imageHeight * scale + offsetY - 20,
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
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
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

                  // Таблица сравнения магазинов
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