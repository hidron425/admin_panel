import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:admin_panel/utils/app_state.dart';

class MallMapEditorScreen extends StatefulWidget {
  const MallMapEditorScreen({super.key});

  @override
  State<MallMapEditorScreen> createState() => _MallMapEditorScreenState();
}

class _MallMapEditorScreenState extends State<MallMapEditorScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  final _mapImageUrlController = TextEditingController();

  String? _selectedMallId;
  Map<String, dynamic>? _mallData;
  List<Map<String, dynamic>> _shops = [];
  bool _loading = true;
  List<String> _mallIds = [];

  String? _draggingShopId;
  Offset? _dragStartShopCenter;
  bool _isDraggingMap = false;

  String? _resizingShopId;
  String? _resizeHandle;
  Offset? _resizeStartPos;
  Rect? _resizeStartRect;

  Size _imageSize = const Size(2045, 731);

  @override
  void initState() {
    super.initState();
    _selectedMallId = AppState.selectedMallId.value;
    AppState.selectedMallId.addListener(_onGlobalMallChanged);
    _loadMallIds();
  }

  @override
  void dispose() {
    AppState.selectedMallId.removeListener(_onGlobalMallChanged);
    _mapImageUrlController.dispose();
    super.dispose();
  }

  void _onGlobalMallChanged() {
    final globalMallId = AppState.selectedMallId.value;
    if (_selectedMallId != globalMallId) {
      setState(() {
        _selectedMallId = globalMallId;
        _loading = true;
      });
      if (_selectedMallId != null) {
        _loadMallData();
      } else {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMallIds() async {
    try {
      final data = await _sb.from('malls').select('firestore_id');
      final ids = (data as List)
          .map((j) => j['firestore_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      if (mounted) setState(() => _mallIds = ids);

      if (ids.isNotEmpty) {
        if (_selectedMallId == null || !ids.contains(_selectedMallId)) {
          _selectedMallId = ids.first;
          AppState.selectedMallId.value = _selectedMallId;
        }
        await _loadMallData();
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('❌ _loadMallIds: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMallData() async {
    if (_selectedMallId == null) return;
    setState(() => _loading = true);
    try {
      final doc = await _sb
          .from('malls')
          .select()
          .eq('firestore_id', _selectedMallId!)
          .maybeSingle();

      if (doc != null) {
        _mallData = Map<String, dynamic>.from(doc);
        _mapImageUrlController.text = (doc['map_image_url'] as String?) ?? '';
        final w = doc['image_width'];
        final h = doc['image_height'];
        if (w != null && h != null) {
          _imageSize = Size((w as num).toDouble(), (h as num).toDouble());
        }
      } else {
        _mallData = {
          'map_image_url': '',
          'image_width': _imageSize.width,
          'image_height': _imageSize.height,
        };
        _mapImageUrlController.text = '';
      }
      await _loadShops();
    } catch (e) {
      debugPrint('❌ _loadMallData: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadShops() async {
    try {
      final data = await _sb
          .from('shops')
          .select()
          .eq('mall_id', _selectedMallId!);
      if (mounted) {
        setState(() {
          _shops = (data as List).map((j) {
            final m = Map<String, dynamic>.from(j);
            m['id'] = m['firestore_id'];
            m['mapX'] = m['map_x'];
            m['mapY'] = m['map_y'];
            m['mapWidth'] = m['map_width'];
            m['mapHeight'] = m['map_height'];
            return m;
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('❌ _loadShops: $e');
    }
  }

  void _updateShopPosition(String shopId, double x, double y) {
    final index = _shops.indexWhere((s) => s['id'] == shopId);
    if (index == -1) return;
    setState(() {
      _shops[index]['mapX'] = x.clamp(0.0, 1.0);
      _shops[index]['mapY'] = y.clamp(0.0, 1.0);
      _shops[index]['map_x'] = _shops[index]['mapX'];
      _shops[index]['map_y'] = _shops[index]['mapY'];
    });
  }

  void _updateShopSize(String shopId, double width, double height) {
    final index = _shops.indexWhere((s) => s['id'] == shopId);
    if (index == -1) return;
    setState(() {
      _shops[index]['mapWidth'] = width.clamp(0.01, 1.0);
      _shops[index]['mapHeight'] = height.clamp(0.01, 1.0);
      _shops[index]['map_width'] = _shops[index]['mapWidth'];
      _shops[index]['map_height'] = _shops[index]['mapHeight'];
    });
  }

  Future<void> _saveAllShops() async {
    try {
      for (final shop in _shops) {
        final id = shop['id'];
        await _sb.from('shops').update({
          'map_x': shop['mapX'] ?? 0.5,
          'map_y': shop['mapY'] ?? 0.5,
          'map_width': shop['mapWidth'] ?? 0.1,
          'map_height': shop['mapHeight'] ?? 0.1,
        }).eq('firestore_id', id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Позиции магазинов сохранены')),
        );
      }
    } catch (e) {
      debugPrint('❌ _saveAllShops: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _updateBackgroundImage() async {
    final newUrl = _mapImageUrlController.text.trim();
    try {
      await _sb.from('malls').upsert({
        'firestore_id': _selectedMallId,
        'map_image_url': newUrl,
        'image_width': _imageSize.width,
        'image_height': _imageSize.height,
      }, onConflict: 'firestore_id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фоновое изображение обновлено')),
        );
        setState(() {
          _mallData?['map_image_url'] = newUrl;
        });
      }
    } catch (e) {
      debugPrint('❌ _updateBackgroundImage: $e');
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
    final url = _mallData?['map_image_url'] as String? ?? '';
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
    final shop = _shops.firstWhere((s) => s['id'] == shopId);
    final containerSize = Size(
      _resizeStartRect!.width / ((shop['mapWidth'] as num?)?.toDouble() ?? 0.1),
      _resizeStartRect!.height / ((shop['mapHeight'] as num?)?.toDouble() ?? 0.1),
    );
    final delta = currentPos - _resizeStartPos!;
    final deltaFractional = Offset(
      delta.dx / containerSize.width,
      delta.dy / containerSize.height,
    );

    double x = (shop['mapX'] as num?)?.toDouble() ?? 0.5;
    double y = (shop['mapY'] as num?)?.toDouble() ?? 0.5;
    double w = (shop['mapWidth'] as num?)?.toDouble() ?? 0.1;
    double h = (shop['mapHeight'] as num?)?.toDouble() ?? 0.1;

    switch (_resizeHandle) {
      case 'bottomRight':
        w = (w + deltaFractional.dx).clamp(0.01, 1.0);
        h = (h + deltaFractional.dy).clamp(0.01, 1.0);
        break;
      case 'topLeft':
        final newW = (w - deltaFractional.dx).clamp(0.01, 1.0);
        final newH = (h - deltaFractional.dy).clamp(0.01, 1.0);
        x = x + (w - newW) / 2;
        y = y + (h - newH) / 2;
        w = newW;
        h = newH;
        break;
      case 'topRight':
        final newW = (w + deltaFractional.dx).clamp(0.01, 1.0);
        final newH = (h - deltaFractional.dy).clamp(0.01, 1.0);
        x = x - (newW - w) / 2;
        y = y + (h - newH) / 2;
        w = newW;
        h = newH;
        break;
      case 'bottomLeft':
        final newW = (w - deltaFractional.dx).clamp(0.01, 1.0);
        final newH = (h + deltaFractional.dy).clamp(0.01, 1.0);
        x = x + (w - newW) / 2;
        y = y - (newH - h) / 2;
        w = newW;
        h = newH;
        break;
      case 'top':
        final newH = (h - deltaFractional.dy).clamp(0.01, 1.0);
        y = y + (h - newH) / 2;
        h = newH;
        break;
      case 'bottom':
        final newH2 = (h + deltaFractional.dy).clamp(0.01, 1.0);
        y = y - (newH2 - h) / 2;
        h = newH2;
        break;
      case 'left':
        final newW = (w - deltaFractional.dx).clamp(0.01, 1.0);
        x = x + (w - newW) / 2;
        w = newW;
        break;
      case 'right':
        final newW2 = (w + deltaFractional.dx).clamp(0.01, 1.0);
        x = x - (newW2 - w) / 2;
        w = newW2;
        break;
    }
    _updateShopPosition(shopId, x, y);
    _updateShopSize(shopId, w, h);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_mallIds.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Редактор карты ТЦ')),
        body: const Center(child: Text('Нет ТЦ. Создайте в разделе "Профили ТЦ".')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактор карты ТЦ'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedMallId,
              items: _mallIds
                  .map((id) => DropdownMenuItem(value: id, child: Text(id)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedMallId = v;
                  AppState.selectedMallId.value = v;
                  _loading = true;
                });
                _loadMallData();
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: _isDraggingMap
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
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
                    const Text('Фоновое изображение карты',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _mapImageUrlController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Оставьте пустым для карты по умолчанию',
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
            const Text('Перетаскивайте магазины, меняйте размер за уголки',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final containerWidth = constraints.maxWidth;
                final containerHeight =
                    containerWidth * (_imageSize.height / _imageSize.width);
                return SizedBox(
                  width: containerWidth,
                  height: containerHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(child: _buildMapBackground()),
                      for (final shop in _shops)
                        if (shop['mapX'] != null && shop['mapY'] != null) ...[
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
                                final fractional = _toFractionalOffset(
                                    newCenter, Size(containerWidth, containerHeight));
                                _updateShopPosition(shop['id'], fractional.dx, fractional.dy);
                                _dragStartShopCenter = newCenter;
                              },
                              onPointerUp: (event) {
                                _draggingShopId = null;
                                setState(() => _isDraggingMap = false);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _draggingShopId == shop['id']
                                        ? Colors.red
                                        : Colors.blue,
                                    width: 2,
                                  ),
                                  color: (_draggingShopId == shop['id']
                                          ? Colors.red
                                          : Colors.blue)
                                      .withOpacity(0.15),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(shop['icon'] ?? '🛍️',
                                        style: const TextStyle(fontSize: 18)),
                                    const SizedBox(height: 2),
                                    Text(
                                      shop['name'] ?? shop['id'],
                                      style: const TextStyle(
                                          fontSize: 8, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _buildResizeHandle('topLeft',
                              _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('topRight',
                              _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('bottomLeft',
                              _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('bottomRight',
                              _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('top',
                              _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('bottom',
                              _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('left',
                              _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
                          _buildResizeHandle('right',
                              _shopRect(shop, Size(containerWidth, containerHeight)), shop['id']),
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
                      Text(shop['name'] ?? shopId,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: shop['mapX']?.toString() ?? '0.5',
                              decoration: const InputDecoration(
                                  labelText: 'X', border: OutlineInputBorder()),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
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
                              decoration: const InputDecoration(
                                  labelText: 'Y', border: OutlineInputBorder()),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
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
                              decoration: const InputDecoration(
                                  labelText: 'Ширина', border: OutlineInputBorder()),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
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
                              decoration: const InputDecoration(
                                  labelText: 'Высота', border: OutlineInputBorder()),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
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