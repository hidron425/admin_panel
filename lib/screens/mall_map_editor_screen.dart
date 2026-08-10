import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MallMapEditorScreen extends StatefulWidget {
  const MallMapEditorScreen({super.key});

  @override
  State<MallMapEditorScreen> createState() => _MallMapEditorScreenState();
}

class _MallMapEditorScreenState extends State<MallMapEditorScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _mapImageUrlController = TextEditingController();

  String? _selectedMallId;
  Map<String, dynamic>? _mallData;
  List<Map<String, dynamic>> _shops = [];
  bool _loading = true;
  List<String> _mallIds = [];

  // Для перетаскивания магазина
  String? _draggingShopId;
  Offset? _dragStartShopCenter;
  bool _isDraggingMap = false;

  // Для изменения размера
  String? _resizingShopId;
  String? _resizeHandle; // 'topLeft', 'topRight', 'bottomLeft', 'bottomRight', 'top', 'bottom', 'left', 'right'
  Offset? _resizeStartPos; // позиция на экране в момент начала
  Rect? _resizeStartRect;  // исходный прямоугольник магазина в экранных координатах

  Size _imageSize = const Size(2045, 731);

  @override
  void initState() {
    super.initState();
    _loadMallIds();
  }

  @override
  void dispose() {
    _mapImageUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadMallIds() async {
    final shopsSnap = await _firestore.collection('shops').get();
    final ids = shopsSnap.docs
        .map((doc) => (doc.data()['mallId'] as String?) ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    setState(() => _mallIds = ids);
    if (_mallIds.isNotEmpty) {
      _selectedMallId = _mallIds.first;
      await _loadMallData();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMallData() async {
    if (_selectedMallId == null) return;
    setState(() => _loading = true);
    final doc = await _firestore.collection('malls').doc(_selectedMallId).get();
    if (doc.exists) {
      _mallData = doc.data()!;
      final url = _mallData?['mapImageUrl'] as String? ?? '';
      _mapImageUrlController.text = url;
      final w = _mallData?['imageWidth'];
      final h = _mallData?['imageHeight'];
      if (w != null && h != null) {
        _imageSize = Size((w as num).toDouble(), (h as num).toDouble());
      }
    } else {
      _mallData = {
        'mapImageUrl': '',
        'imageWidth': _imageSize.width,
        'imageHeight': _imageSize.height,
      };
      _mapImageUrlController.text = '';
    }
    await _loadShops();
    setState(() => _loading = false);
  }

  Future<void> _loadShops() async {
    final snap = await _firestore
        .collection('shops')
        .where('mallId', isEqualTo: _selectedMallId)
        .get();
    setState(() {
      _shops = snap.docs.map((d) => {
            'id': d.id,
            ...d.data() as Map<String, dynamic>,
          }).toList();
    });
  }

  void _updateShopPosition(String shopId, double x, double y) {
    final index = _shops.indexWhere((s) => s['id'] == shopId);
    if (index == -1) return;
    _shops[index]['mapX'] = x.clamp(0.0, 1.0);
    _shops[index]['mapY'] = y.clamp(0.0, 1.0);
    setState(() {});
  }

  void _updateShopSize(String shopId, double width, double height) {
    final index = _shops.indexWhere((s) => s['id'] == shopId);
    if (index == -1) return;
    _shops[index]['mapWidth'] = width.clamp(0.01, 1.0);
    _shops[index]['mapHeight'] = height.clamp(0.01, 1.0);
    setState(() {});
  }

  Future<void> _saveAllShops() async {
    final batch = _firestore.batch();
    for (final shop in _shops) {
      final ref = _firestore.collection('shops').doc(shop['id']);
      batch.update(ref, {
        'mapX': shop['mapX'] ?? 0.5,
        'mapY': shop['mapY'] ?? 0.5,
        'mapWidth': shop['mapWidth'] ?? 0.1,
        'mapHeight': shop['mapHeight'] ?? 0.1,
      });
    }
    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Позиции магазинов сохранены')),
      );
    }
  }

  Future<void> _updateBackgroundImage() async {
    final newUrl = _mapImageUrlController.text.trim();
    await _firestore.collection('malls').doc(_selectedMallId).set({
      'mapImageUrl': newUrl,
      'imageWidth': _imageSize.width,
      'imageHeight': _imageSize.height,
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фоновое изображение обновлено')),
      );
      setState(() {
        _mallData?['mapImageUrl'] = newUrl;
      });
    }
  }

  Rect _shopRect(Map<String, dynamic> shop, Size containerSize) {
    final double x = (shop['mapX'] as num?)?.toDouble() ?? 0.5;
    final double y = (shop['mapY'] as num?)?.toDouble() ?? 0.5;
    final double w = (shop['mapWidth'] as num?)?.toDouble() ?? 0.1;
    final double h = (shop['mapHeight'] as num?)?.toDouble() ?? 0.1;

    final left = (x - w / 2) * containerSize.width;
    final top = (y - h / 2) * containerSize.height;
    return Rect.fromLTWH(left, top, w * containerSize.width, h * containerSize.height);
  }

  Offset _toFractionalOffset(Offset screenPos, Size containerSize) {
    final x = (screenPos.dx / containerSize.width).clamp(0.0, 1.0);
    final y = (screenPos.dy / containerSize.height).clamp(0.0, 1.0);
    return Offset(x, y);
  }

  Widget _buildMapBackground() {
    final url = _mallData?['mapImageUrl'] as String? ?? '';
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.fill,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey[200]),
      );
    } else {
      return Image.asset(
        'assets/images/mall_map.png',
        fit: BoxFit.fill,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey[200]),
      );
    }
  }

  // ----------- Ручки для изменения размера ----------
  Widget _buildResizeHandle(String handle, Rect rect, String shopId) {
    double left, top;
    switch (handle) {
      case 'topLeft':
        left = rect.left - 4;
        top = rect.top - 4;
        break;
      case 'topRight':
        left = rect.right - 4;
        top = rect.top - 4;
        break;
      case 'bottomLeft':
        left = rect.left - 4;
        top = rect.bottom - 4;
        break;
      case 'bottomRight':
        left = rect.right - 4;
        top = rect.bottom - 4;
        break;
      case 'top':
        left = rect.center.dx - 4;
        top = rect.top - 4;
        break;
      case 'bottom':
        left = rect.center.dx - 4;
        top = rect.bottom - 4;
        break;
      case 'left':
        left = rect.left - 4;
        top = rect.center.dy - 4;
        break;
      case 'right':
        left = rect.right - 4;
        top = rect.center.dy - 4;
        break;
      default:
        return const SizedBox.shrink();
    }
    return Positioned(
      left: left,
      top: top,
      width: 12,
      height: 12,
      child: Listener(
        onPointerDown: (event) {
          _resizingShopId = shopId;
          _resizeHandle = handle;
          _resizeStartPos = event.position;
          _resizeStartRect = rect;
          setState(() => _isDraggingMap = true);
        },
        onPointerMove: (event) {
          if (_resizingShopId != shopId || _resizeHandle == null) return;
          _resizeRect(shopId, event.position);
        },
        onPointerUp: (event) {
          _resizingShopId = null;
          _resizeHandle = null;
          setState(() => _isDraggingMap = false);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 1),
          ),
        ),
      ),
    );
  }

  void _resizeRect(String shopId, Offset currentPos) {
    if (_resizeStartPos == null || _resizeStartRect == null) return;
    final containerSize = Size(
      _resizeStartRect!.width / (_shops.firstWhere((s) => s['id'] == shopId)['mapWidth'] ?? 0.1),
      _resizeStartRect!.height / (_shops.firstWhere((s) => s['id'] == shopId)['mapHeight'] ?? 0.1),
    );
    // Преобразуем смещение в экранных координатах в изменение долей
    final delta = currentPos - _resizeStartPos!;
    final deltaFractional = Offset(
      delta.dx / containerSize.width,
      delta.dy / containerSize.height,
    );

    final shop = _shops.firstWhere((s) => s['id'] == shopId);
    double x = (shop['mapX'] as num?)?.toDouble() ?? 0.5;
    double y = (shop['mapY'] as num?)?.toDouble() ?? 0.5;
    double w = (shop['mapWidth'] as num?)?.toDouble() ?? 0.1;
    double h = (shop['mapHeight'] as num?)?.toDouble() ?? 0.1;

    // В зависимости от handle меняем размер и положение
    switch (_resizeHandle) {
      case 'bottomRight':
        w = (w + deltaFractional.dx).clamp(0.01, 1.0);
        h = (h + deltaFractional.dy).clamp(0.01, 1.0);
        // центр смещается на половину изменения ширины/высоты? Нет, лучше оставить левый-верхний угол неподвижным.
        // bottomRight – правый-нижний угол двигаем, left-top остаётся.
        // Тогда новый центр будет:
        x = (shop['mapX'] - (shop['mapWidth'] ?? 0.1)/2 + w/2).clamp(0.0, 1.0);
        y = (shop['mapY'] - (shop['mapHeight'] ?? 0.1)/2 + h/2).clamp(0.0, 1.0);
        break;
      case 'topLeft':
        // двигаем левый-верхний угол, правый-нижний фиксирован.
        double newW = (w - deltaFractional.dx).clamp(0.01, 1.0);
        double newH = (h - deltaFractional.dy).clamp(0.01, 1.0);
        x = (shop['mapX'] + (shop['mapWidth'] ?? 0.1)/2 - newW/2).clamp(0.0, 1.0);
        y = (shop['mapY'] + (shop['mapHeight'] ?? 0.1)/2 - newH/2).clamp(0.0, 1.0);
        w = newW;
        h = newH;
        break;
      case 'topRight':
        double newW = (w + deltaFractional.dx).clamp(0.01, 1.0);
        double newH = (h - deltaFractional.dy).clamp(0.01, 1.0);
        x = (shop['mapX'] - (shop['mapWidth'] ?? 0.1)/2 + newW/2).clamp(0.0, 1.0);
        y = (shop['mapY'] + (shop['mapHeight'] ?? 0.1)/2 - newH/2).clamp(0.0, 1.0);
        w = newW;
        h = newH;
        break;
      case 'bottomLeft':
        double newW = (w - deltaFractional.dx).clamp(0.01, 1.0);
        double newH = (h + deltaFractional.dy).clamp(0.01, 1.0);
        x = (shop['mapX'] + (shop['mapWidth'] ?? 0.1)/2 - newW/2).clamp(0.0, 1.0);
        y = (shop['mapY'] - (shop['mapHeight'] ?? 0.1)/2 + newH/2).clamp(0.0, 1.0);
        w = newW;
        h = newH;
        break;
      case 'top':
        double newH = (h - deltaFractional.dy).clamp(0.01, 1.0);
        y = (shop['mapY'] + (shop['mapHeight'] ?? 0.1)/2 - newH/2).clamp(0.0, 1.0);
        h = newH;
        break;
      case 'bottom':
        double newH2 = (h + deltaFractional.dy).clamp(0.01, 1.0);
        y = (shop['mapY'] - (shop['mapHeight'] ?? 0.1)/2 + newH2/2).clamp(0.0, 1.0);
        h = newH2;
        break;
      case 'left':
        double newW = (w - deltaFractional.dx).clamp(0.01, 1.0);
        x = (shop['mapX'] + (shop['mapWidth'] ?? 0.1)/2 - newW/2).clamp(0.0, 1.0);
        w = newW;
        break;
      case 'right':
        double newW2 = (w + deltaFractional.dx).clamp(0.01, 1.0);
        x = (shop['mapX'] - (shop['mapWidth'] ?? 0.1)/2 + newW2/2).clamp(0.0, 1.0);
        w = newW2;
        break;
    }
    _updateShopPosition(shopId, x, y);
    _updateShopSize(shopId, w, h);
  }

  // ----------- Основное построение ----------
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_mallIds.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Редактор карты ТЦ')),
        body: const Center(child: Text('Нет магазинов с mallId.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактор карты ТЦ'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedMallId,
              items: _mallIds.map((id) => DropdownMenuItem(value: id, child: Text(id))).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedMallId = v;
                  _loading = true;
                });
                _loadMallData();
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: _isDraggingMap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Фоновое изображение карты', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _mapImageUrlController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Оставьте пустым, чтобы использовать карту по умолчанию',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _updateBackgroundImage,
                          icon: const Icon(Icons.upload),
                          label: const Text('Обновить'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      width: double.infinity,
                      child: _buildMapBackground(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Перетаскивайте магазины, меняйте размер за уголки', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final containerWidth = constraints.maxWidth;
                final containerHeight = containerWidth * (_imageSize.height / _imageSize.width);
                return SizedBox(
                  width: containerWidth,
                  height: containerHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(child: _buildMapBackground()),
                      for (final shop in _shops)
                        if (shop['mapX'] != null && shop['mapY'] != null) ...[
                          // Прямоугольник магазина
                          Positioned.fromRect(
                            rect: _shopRect(shop, Size(containerWidth, containerHeight)),
                            child: Listener(
                              onPointerDown: (event) {
                                _draggingShopId = shop['id'];
                                final rect = _shopRect(shop, Size(containerWidth, containerHeight));
                                _dragStartShopCenter = Offset(rect.center.dx, rect.center.dy);
                                setState(() => _isDraggingMap = true);
                              },
                              onPointerMove: (event) {
                                if (_draggingShopId != shop['id']) return;
                                final delta = event.position - _dragStartShopCenter!;
                                final newCenter = _dragStartShopCenter! + delta;
                                final fractional = _toFractionalOffset(newCenter, Size(containerWidth, containerHeight));
                                _updateShopPosition(shop['id'], fractional.dx, fractional.dy);
                                _dragStartShopCenter = newCenter;
                              },
                              onPointerUp: (event) {
                                _draggingShopId = null;
                                setState(() => _isDraggingMap = false);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: _draggingShopId == shop['id'] ? Colors.red : Colors.blue, width: 2),
                                  color: (_draggingShopId == shop['id'] ? Colors.red : Colors.blue).withOpacity(0.15),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(shop['icon'] ?? '🛍️', style: const TextStyle(fontSize: 18)),
                                    const SizedBox(height: 2),
                                    Text(
                                      shop['name'] ?? shop['id'],
                                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Ручки изменения размера
                          _buildResizeHandle('topLeft', _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('topRight', _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('bottomLeft', _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('bottomRight', _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('top', _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('bottom', _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('left', _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('right', _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                        ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Text('Точная настройка', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._shops.map((shop) {
              final shopId = shop['id'];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop['name'] ?? shopId, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: shop['mapX']?.toString() ?? '0.5',
                              decoration: const InputDecoration(labelText: 'X', border: OutlineInputBorder()),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) {
                                final val = double.tryParse(v) ?? 0.5;
                                _updateShopPosition(shopId, val, shop['mapY'] ?? 0.5);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: shop['mapY']?.toString() ?? '0.5',
                              decoration: const InputDecoration(labelText: 'Y', border: OutlineInputBorder()),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) {
                                final val = double.tryParse(v) ?? 0.5;
                                _updateShopPosition(shopId, shop['mapX'] ?? 0.5, val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: shop['mapWidth']?.toString() ?? '0.1',
                              decoration: const InputDecoration(labelText: 'Ширина', border: OutlineInputBorder()),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) {
                                final val = double.tryParse(v) ?? 0.1;
                                _updateShopSize(shopId, val, shop['mapHeight'] ?? 0.1);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: shop['mapHeight']?.toString() ?? '0.1',
                              decoration: const InputDecoration(labelText: 'Высота', border: OutlineInputBorder()),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) {
                                final val = double.tryParse(v) ?? 0.1;
                                _updateShopSize(shopId, shop['mapWidth'] ?? 0.1, val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: _saveAllShops,
                icon: const Icon(Icons.save),
                label: const Text('Сохранить все позиции'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}