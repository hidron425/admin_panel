// lib/screens/zone_editor_screen.dart
//
// Редактор зон магазинов: прямоугольники И произвольные контуры.
//
// Внутри всё — полигон. Прямоугольник это полигон из 4 вершин, поэтому
// отрисовка, хит-тест, undo и сохранение одинаковы для любых форм.
//
// Инструменты:
//   Выделение     — выбрать зону, двигать её, тянуть вершины, вставлять новые
//   Прямоугольник — протянуть рамку (быстрый путь для обычных магазинов)
//   Контур        — клик за кликом обвести L/T/U-образный магазин
//   Вход          — поставить дверь на границе контура
//   Область подписи — обвести контур, внутри которого стоит название
//   Рука          — панорама/зум плана
//
// Зависимости: flutter + supabase_flutter. Ничего нового.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../map/shop_zone.dart';
import '../theme/admin_theme.dart';
import 'package:admin_panel/utils/audit.dart';
import 'package:flutter/gestures.dart';

/// Цвета клиентской карты — для режима «Предпросмотр».
class ClientZoneStyle {
  static const Color idle = Color(0x1A1E5AFF);
  static const Color hover = Color(0x4D1E5AFF);
  static const Color selected = Color(0x661E5AFF);
  static const Color border = Color(0xFF1E5AFF);
  static const Color visited = Color(0x2616A34A);
}

/// Оранжевый маршрута клиента — им помечаем ручной якорь подписи,
/// чтобы он не путался с зелёной точкой входа.
const Color kLabelAnchorColor = Color(0xFFFF6B35);

/// Дефолтная область подписи: 80% × 55% от габаритов зоны, по центру.
/// Ровно те же доли, что в клиентском _effectiveLabelRect — иначе
/// предпросмотр и пунктирный дефолт инструмента врут.
/// Живёт только в памяти — в БД попадает лишь когда её тронут.
Rect? defaultLabelRect(ShopZone? zone) {
  if (zone == null) return null;
  final b = zone.bounds;
  return Rect.fromCenter(
    center: b.center,
    width: b.width * 0.8,
    height: b.height * 0.55,
  );
}

List<Offset> rectToPoints(Rect r) =>
    [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];

enum _Tool { select, rect, polygon, entry, labelAnchor, pan }

enum _PreviewMode { off, idle, hover, visited }

enum _HitKind { none, vertex, edge, body }

class _Hit {
  final _HitKind kind;
  final String? storeId;
  final int index;
  final Offset? point;
  const _Hit(this.kind, {this.storeId, this.index = -1, this.point});
  static const none = _Hit(_HitKind.none);
}

enum _Drag { none, vertex, zone, rect, labelVertex, labelMove }

class _Mall {
  final String id;
  final String name;
  final String? mapImageUrl;
  final Offset? entrance;
  _Mall({required this.id, required this.name, this.mapImageUrl, this.entrance});

  factory _Mall.fromRow(Map<String, dynamic> row) {
    final ex = row['entrance_x'] as num?;
    final ey = row['entrance_y'] as num?;
    return _Mall(
      id: (row['firestore_id'] ?? row['id'] ?? '').toString(),
      name: (row['name'] ?? 'Без названия').toString(),
      mapImageUrl: row['map_image_url'] as String?,
      entrance: (ex != null && ey != null)
          ? Offset(ex.toDouble(), ey.toDouble())
          : null,
    );
  }
}

class _ZoneRow {
  final String id;
  final String name;
  ShopZone? zone;
  ShopZone? saved;

  /// shops.label_x/label_y. Лежит здесь, а не в [zone], потому что это
  /// не часть контура: в dirty-учёт и в снимки undo якорь не входит,
  /// пишется в БД сразу и существует даже у магазина без зоны.
  Offset? labelOverride;

  /// shops.label_angle — угол подписи в градусах. Там же и по той же
  /// причине, что [labelOverride].
  double? labelAngle;

  /// shops.label_rect = [x, y, w, h] (0..1, от левого верхнего угла).
  /// Задан -> клиент рисует подпись внутри него. Там же и по той же
  /// причине, что [labelOverride].
  Rect? labelRect;

  /// shops.label_polygon = [[x,y],...] (0..1). Старше прямоугольника:
  /// задан -> подпись считается по его габаритам, а label_rect гасится
  /// при первой же правке.
  List<Offset>? labelPolygon;

  _ZoneRow({
    required this.id,
    required this.name,
    this.zone,
    this.saved,
    this.labelOverride,
    this.labelAngle,
    this.labelRect,
    this.labelPolygon,
  });

  bool get isPlaced => zone != null;

  bool get isDirty {
    if (zone == null && saved == null) return false;
    if (zone == null || saved == null) return true;
    return !zone!.sameAs(saved);
  }
}

/// Состояние, которое меняется на каждый кадр перетаскивания.
/// Живёт отдельно от State, чтобы во время драга перерисовывался ТОЛЬКО
/// холст, а не список из 90 магазинов и тулбар.
class _CanvasModel extends ChangeNotifier {
  List<_ZoneRow> stores = const [];
  String? selectedId;
  String? hoverId;
  int selectedVertex = -1;
  int hoverVertex = -1;
  Offset? hoverEdgePoint; // точка-«плюс» на ребре, координаты холста
  List<Offset> draft = const []; // рисуемый контур, нормализованные координаты
  Offset? cursor; // курсор, нормализованные координаты
  Rect? draftRect; // рисуемая рамка, нормализованная
  Set<int> badEdges = const {};

  // Область подписи: своё состояние наведения и свой черновик, чтобы не
  // мешать выбору магазина и рисованию контура зоны.
  int labelActiveVertex = -1;
  int labelHoverVertex = -1;
  Offset? labelHoverEdge;
  List<Offset> labelDraft = const [];
  double scale = 1;
  Size canvas = Size.zero;
  Offset? entrance;
  _PreviewMode preview = _PreviewMode.off;
  bool showGrid = true;
  int gridDivisions = 20;

  ShopZone? get selectedZone {
    for (final s in stores) {
      if (s.id == selectedId) return s.zone;
    }
    return null;
  }

  void bump() => notifyListeners();
}

// ===========================================================================

class ZoneEditorScreen extends StatefulWidget {
  final String? initialMallId;
  const ZoneEditorScreen({super.key, this.initialMallId});

  @override
  State<ZoneEditorScreen> createState() => _ZoneEditorScreenState();
}

class _ZoneEditorScreenState extends State<ZoneEditorScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  final _m = _CanvasModel();

  List<_Mall> _malls = [];
  _Mall? _mall;
  List<_ZoneRow> _stores = [];
  bool _loadingMalls = true;
  bool _loadingStores = false;
  bool _saving = false;

  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Size? _imageSize;
  Object? _imageError;

  _Tool _tool = _Tool.select;
  bool _spaceHeld = false;
  bool _snapToGrid = false;
  bool _magnet = true;
  String _search = '';

  final TransformationController _view = TransformationController();
  final FocusNode _focus = FocusNode();

  _Drag _drag = _Drag.none;
  Offset _dragStartCanvas = Offset.zero;
  ShopZone? _dragStartZone;

  // Область подписи: какую вершину тянем и с чего начали. Значения
  // «до правки» нужны, чтобы откатиться, если запись не прошла.
  int _labelVertex = -1;
  List<Offset>? _labelPolyAtDragStart;
  List<Offset>? _labelPolyBeforeEdit;
  Rect? _labelRectBeforeEdit;

  final List<Map<String, ShopZone?>> _undo = [];
  final List<Map<String, ShopZone?>> _redo = [];
  static const int _maxHistory = 60;

  final _xCtrl = TextEditingController();
  final _yCtrl = TextEditingController();
  final _wCtrl = TextEditingController();
  final _hCtrl = TextEditingController();
  final _angleCtrl = TextEditingController();
  final _xFocus = FocusNode();
  final _yFocus = FocusNode();
  final _wFocus = FocusNode();
  final _hFocus = FocusNode();
  final _angleFocus = FocusNode();
  final _searchFocus = FocusNode();

  // Пороги попадания в ЭКРАННЫХ пикселях — делим на масштаб при проверке.
  static const double _vertexHit = 11;
  static const double _edgeHit = 10;
  static const double _closeHit = 12;
  static const double _magnetVertex = 9;
  static const double _magnetEdge = 7;

  double get _scale => _m.scale;
  double _cx(double screenPx) => screenPx / _scale;

  @override
  void initState() {
    super.initState();
    _view.addListener(_onViewChanged);
    _loadMalls();
  }

  @override
  void dispose() {
    _detachImage();
    _view.removeListener(_onViewChanged);
    _view.dispose();
    _focus.dispose();
    _m.dispose();
    for (final c in [_xCtrl, _yCtrl, _wCtrl, _hCtrl, _angleCtrl]) {
      c.dispose();
    }
    for (final f in [
      _xFocus,
      _yFocus,
      _wFocus,
      _hFocus,
      _angleFocus,
      _searchFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  // =========================================================================
  // Загрузка
  // =========================================================================

  Future<void> _loadMalls() async {
    try {
      final data = await _sb.from('malls').select();
      final malls = (data as List)
          .map((r) => _Mall.fromRow(Map<String, dynamic>.from(r)))
          .where((m) => m.id.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      _Mall? initial;
      for (final m in malls) {
        if (m.id == widget.initialMallId) initial = m;
      }
      initial ??= malls.isNotEmpty ? malls.first : null;

      if (!mounted) return;
      setState(() {
        _malls = malls;
        _loadingMalls = false;
      });
      if (initial != null) await _selectMall(initial);
    } catch (e) {
      debugPrint('❌ _loadMalls: $e');
      if (mounted) setState(() => _loadingMalls = false);
    }
  }

  Future<void> _selectMall(_Mall mall) async {
    if (_dirtyCount > 0 && await _confirmDiscard() != true) return;
    setState(() {
      _mall = mall;
      _stores = [];
      _imageSize = null;
      _imageError = null;
      _loadingStores = true;
      _undo.clear();
      _redo.clear();
      _view.value = Matrix4.identity();
    });
    _m
      ..stores = const []
      ..selectedId = null
      ..hoverId = null
      ..selectedVertex = -1
      ..draft = const []
      ..entrance = mall.entrance
      ..bump();
    _attachImage(mall.mapImageUrl);
    await _loadStores(mall.id);
  }

  Future<void> _loadStores(String mallId) async {
    try {
      final data = await _sb
          .from('shops')
          .select(
              'firestore_id, name, map_x, map_y, map_width, map_height, map_polygon, entry_x, entry_y, label_x, label_y, label_angle, label_rect, label_polygon')
          .eq('mall_id', mallId);

      final stores = (data as List)
          .map((raw) {
            final row = Map<String, dynamic>.from(raw);
            // Якорь и угол снимаем с модели и держим в _ZoneRow: два
            // источника правды разошлись бы сразу после «Очистить якорь».
            final zone = ShopZone.fromDb(row)?.withoutLabelPlacement();
            return _ZoneRow(
              id: (row['firestore_id'] ?? '').toString(),
              name: (row['name'] ?? 'Без названия').toString(),
              zone: zone,
              saved: zone,
              labelOverride: ShopZone.readLabelOverride(row),
              labelAngle: ShopZone.readLabelAngle(row),
              labelRect: ShopZone.readLabelRect(row),
              labelPolygon: ShopZone.readLabelPolygon(row),
            );
          })
          .where((s) => s.id.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        _stores = stores;
        _loadingStores = false;
      });
      _m
        ..stores = stores
        ..selectedId = stores.isNotEmpty ? stores.first.id : null
        ..bump();
      _syncFields();
    } catch (e) {
      debugPrint('❌ _loadStores: $e');
      if (mounted) setState(() => _loadingStores = false);
    }
  }

  void _attachImage(String? url) {
    _detachImage();
    if (url == null || url.trim().isEmpty) {
      setState(() => _imageError = 'no_url');
      return;
    }
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() => _imageSize =
            Size(info.image.width.toDouble(), info.image.height.toDouble()));
      },
      onError: (e, _) {
        if (!mounted) return;
        setState(() => _imageError = e);
      },
    );
    stream.addListener(listener);
    _imageStream = stream;
    _imageListener = listener;
  }

  void _detachImage() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  double get _aspect => (_imageSize != null && _imageSize!.height > 0)
      ? _imageSize!.width / _imageSize!.height
      : 16 / 9;

  bool get _mapReady => _imageSize != null && _imageError == null;

  // =========================================================================
  // Утилиты
  // =========================================================================

  _ZoneRow? get _selected {
    for (final s in _stores) {
      if (s.id == _m.selectedId) return s;
    }
    return null;
  }

  int get _dirtyCount => _stores.where((s) => s.isDirty).length;

  List<_ZoneRow> get _filtered {
    if (_search.trim().isEmpty) return _stores;
    final q = _search.toLowerCase();
    return _stores.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  void _onViewChanged() {
    final s = _view.value.getMaxScaleOnAxis();
    if ((s - _m.scale).abs() > 0.001) {
      _m
        ..scale = s
        ..bump();
      setState(() {}); // масштаб показан в бейдже
    }
  }

  Offset _toCanvas(Offset n) =>
      Offset(n.dx * _m.canvas.width, n.dy * _m.canvas.height);

  Offset _toNorm(Offset c) =>
      Offset(c.dx / _m.canvas.width, c.dy / _m.canvas.height);

  void _pushUndo() {
    _undo.add({for (final s in _stores) s.id: s.zone});
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(Map<String, ShopZone?> snap) {
    for (final s in _stores) {
      if (snap.containsKey(s.id)) s.zone = snap[s.id];
    }
  }

  void _doUndo() {
    if (_undo.isEmpty) return;
    final current = {for (final s in _stores) s.id: s.zone};
    _restore(_undo.removeLast());
    _redo.add(current);
    _afterZoneChange();
  }

  void _doRedo() {
    if (_redo.isEmpty) return;
    final current = {for (final s in _stores) s.id: s.zone};
    _restore(_redo.removeLast());
    _undo.add(current);
    _afterZoneChange();
  }

  /// Вызывать после любой правки контура: пересчитать предупреждения,
  /// обновить поля и перерисовать.
  void _afterZoneChange({bool full = true}) {
    final zone = _m.selectedZone;
    _m.badEdges =
        zone == null ? const {} : PolygonMath.selfIntersections(zone.points);
    _m.bump();
    _syncFields();
    if (full && mounted) setState(() {});
  }

  void _syncFields() {
    final zone = _m.selectedZone;
    final rect = (zone != null && zone.isRectangle) ? zone.bounds : null;
    void set(TextEditingController c, FocusNode f, double? v) {
      if (f.hasFocus) return;
      c.text = v == null ? '' : v.toStringAsFixed(4);
    }

    set(_xCtrl, _xFocus, rect?.center.dx);
    set(_yCtrl, _yFocus, rect?.center.dy);
    set(_wCtrl, _wFocus, rect?.width);
    set(_hCtrl, _hFocus, rect?.height);

    // Угол — не часть контура, поэтому берём его из строки, а не из зоны.
    final angle = _selected?.labelAngle;
    if (!_angleFocus.hasFocus) {
      _angleCtrl.text = angle == null ? '' : _fmtAngle(angle);
    }
  }

  /// 45.0 -> «45», 45.5 -> «45.5»: в поле не нужен лишний ноль.
  static String _fmtAngle(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  void _applyFields() {
    final store = _selected;
    if (store == null) return;
    double? p(TextEditingController c) =>
        double.tryParse(c.text.replaceAll(',', '.'));
    final x = p(_xCtrl), y = p(_yCtrl), w = p(_wCtrl), h = p(_hCtrl);
    if (x == null || y == null || w == null || h == null) return;
    if (w <= 0 || h <= 0) return;
    _pushUndo();
    store.zone = ShopZone.fromRect(
      ShopZone.clampRectToUnit(
          Rect.fromCenter(center: Offset(x, y), width: w, height: h)),
      entry: store.zone?.entry,
    );
    _afterZoneChange();
  }

  // =========================================================================
  // Привязки
  // =========================================================================

  Offset _gridSnap(Offset canvasPoint) {
    final sx = _m.canvas.width / _m.gridDivisions;
    final sy = _m.canvas.height / _m.gridDivisions;
    return Offset(
      (canvasPoint.dx / sx).round() * sx,
      (canvasPoint.dy / sy).round() * sy,
    );
  }

  /// Магнит к вершинам и рёбрам соседних зон — так общие стены становятся
  /// действительно общими, без щелей и нахлёстов.
  Offset? _magnetSnap(Offset canvasPoint, {String? excludeId}) {
    Offset? best;
    var bestDistance = double.infinity;

    for (final store in _stores) {
      final zone = store.zone;
      if (zone == null || store.id == excludeId) continue;
      for (final v in zone.canvasPoints(_m.canvas)) {
        final d = (v - canvasPoint).distance;
        if (d < _cx(_magnetVertex) && d < bestDistance) {
          bestDistance = d;
          best = v;
        }
      }
    }
    if (best != null) return best;

    for (final store in _stores) {
      final zone = store.zone;
      if (zone == null || store.id == excludeId) continue;
      final hit = PolygonMath.closestOnBoundary(
          zone.canvasPoints(_m.canvas), canvasPoint);
      if (hit.distance < _cx(_magnetEdge) && hit.distance < bestDistance) {
        bestDistance = hit.distance;
        best = hit.point;
      }
    }
    return best;
  }

  Offset _applySnaps(Offset canvasPoint,
      {Offset? from, String? excludeId, bool useMagnet = true}) {
    if (_magnet && useMagnet) {
      final m = _magnetSnap(canvasPoint, excludeId: excludeId);
      if (m != null) return m;
    }
    if (HardwareKeyboard.instance.isShiftPressed && from != null) {
      return PolygonMath.orthoSnap(from, canvasPoint);
    }
    if (_snapToGrid) return _gridSnap(canvasPoint);
    return canvasPoint;
  }

  /// Куда встанет вершина под курсором: привязки (магнит к соседям,
  /// Shift — ровные углы, сетка) плюс зажим в 0..1.
  ///
  /// Общий для контура зоны и для области подписи. У подписи магнит
  /// выключен: липнуть к стенам чужих магазинов ей незачем.
  Offset _vertexTarget(Offset local,
      {Offset? from, String? excludeId, bool useMagnet = true}) {
    final snapped = _applySnaps(local,
        from: from, excludeId: excludeId, useMagnet: useMagnet);
    final n = _toNorm(snapped);
    return Offset(n.dx.clamp(0.0, 1.0), n.dy.clamp(0.0, 1.0));
  }

  // =========================================================================
  // Хит-тест
  // =========================================================================

  /// Попадание в замкнутый контур: вершина -> ребро -> тело.
  ///
  /// Один порядок проверок и одни пороги для контура зоны и для области
  /// подписи — отличается только то, по каким точкам его зовут.
  _Hit _hitPolygon(List<Offset> pts, Offset local, String storeId) {
    for (var i = 0; i < pts.length; i++) {
      if ((pts[i] - local).distance <= _cx(_vertexHit)) {
        return _Hit(_HitKind.vertex, storeId: storeId, index: i);
      }
    }
    final edge = PolygonMath.closestOnBoundary(pts, local);
    if (edge.distance <= _cx(_edgeHit)) {
      return _Hit(_HitKind.edge,
          storeId: storeId, index: edge.edgeIndex, point: edge.point);
    }
    if (PolygonMath.contains(pts, local)) {
      return _Hit(_HitKind.body, storeId: storeId);
    }
    return _Hit.none;
  }

  _Hit _hitTest(Offset local) {
    if (_m.canvas == Size.zero || _m.preview != _PreviewMode.off) {
      return _Hit.none;
    }

    final selectedRow = _selected;
    final selectedZone = selectedRow?.zone;

    // 1-3. Вершина -> ребро (вставка вершины) -> тело выделенной зоны.
    if (selectedZone != null) {
      final hit = _hitPolygon(
          selectedZone.canvasPoints(_m.canvas), local, selectedRow!.id);
      if (hit.kind != _HitKind.none) return hit;
    }

    // 4. Чужие зоны: сначала самые мелкие, чтобы киоск внутри универмага
    //    оставался доступным.
    final others = _stores
        .where((s) => s.zone != null && s.id != _m.selectedId)
        .toList()
      ..sort((a, b) => a.zone!.area.compareTo(b.zone!.area));
    for (final s in others) {
      if (PolygonMath.contains(s.zone!.canvasPoints(_m.canvas), local)) {
        return _Hit(_HitKind.body, storeId: s.id);
      }
    }
    return _Hit.none;
  }

  MouseCursor get _cursor {
    if (_tool == _Tool.pan || _spaceHeld) return SystemMouseCursors.grab;
    if (_tool == _Tool.polygon ||
        _tool == _Tool.entry ||
        _tool == _Tool.labelAnchor) {
      return SystemMouseCursors.precise;
    }
    if (_m.hoverVertex >= 0) return SystemMouseCursors.resizeUpLeftDownRight;
    if (_m.hoverEdgePoint != null) return SystemMouseCursors.copy;
    if (_m.hoverId != null) return SystemMouseCursors.move;
    return SystemMouseCursors.basic;
  }

  // =========================================================================
  // Указатель
  // =========================================================================

  void _onHover(Offset local) {
    if (!_mapReady) return;
    _m.cursor = _toNorm(local);

    if (_tool == _Tool.polygon && _m.draft.isNotEmpty) {
      _m.bump();
      return;
    }
    if (_m.preview != _PreviewMode.off) return;

    // Область подписи ведёт себя как контур зоны: подсветка вершины под
    // курсором и «плюс» на ближайшем ребре.
    if (_tool == _Tool.labelAnchor) {
      final row = _selected;
      final region = row == null ? null : _labelRegionOf(row);
      if (region == null || _m.labelDraft.isNotEmpty) {
        _m.bump();
        return;
      }
      final hit = _hitPolygon(_labelCanvasPoints(region), local, row!.id);
      _m
        ..labelHoverVertex = hit.kind == _HitKind.vertex ? hit.index : -1
        ..labelHoverEdge = hit.kind == _HitKind.edge ? hit.point : null
        ..bump();
      return;
    }

    final hit = _hitTest(local);
    final hoverId = hit.kind == _HitKind.none ? null : hit.storeId;
    _m
      ..hoverId = hoverId
      ..hoverVertex = hit.kind == _HitKind.vertex ? hit.index : -1
      // «Плюс» показываем только на ближайшем ребре и только при наведении —
      // иначе 30 вершин превращаются в 30 плюсиков и кашу.
      ..hoverEdgePoint = hit.kind == _HitKind.edge ? hit.point : null
      ..bump();
  }

  void _onTapUp(Offset local) {
    if (!_mapReady) return;
    _focus.requestFocus();

    switch (_tool) {
      case _Tool.polygon:
        _addDraftVertex(local);
        return;
      case _Tool.entry:
        _setEntry(local);
        return;
      case _Tool.labelAnchor:
        _onLabelTap(local);
        return;
      case _Tool.pan:
        return;
      case _Tool.rect:
      case _Tool.select:
        break;
    }

    final hit = _hitTest(local);

    // Alt+клик по вершине удаляет её. Правую кнопку не используем: в вебе
    // поверх неё всплывает контекстное меню браузера.
    if (hit.kind == _HitKind.vertex &&
        HardwareKeyboard.instance.isAltPressed) {
      _deleteVertex(hit.index);
      return;
    }
    if (hit.kind == _HitKind.vertex) {
      _m
        ..selectedVertex = hit.index
        ..bump();
      return;
    }
    if (hit.kind == _HitKind.body && hit.storeId != _m.selectedId) {
      _m
        ..selectedId = hit.storeId
        ..selectedVertex = -1;
      _afterZoneChange();
    }
  }

  void _onPanStart(Offset local) {
    if (!_mapReady || _m.preview != _PreviewMode.off) return;
    if (_tool == _Tool.labelAnchor) {
      _startLabelDrag(local);
      return;
    }
    if (_tool == _Tool.polygon || _tool == _Tool.entry) return;

    if (_tool == _Tool.rect) {
      _startRect(local);
      return;
    }

    final hit = _hitTest(local);

    switch (hit.kind) {
      case _HitKind.vertex:
        _pushUndo();
        _drag = _Drag.vertex;
        _dragStartZone = _selected?.zone;
        _m
          ..selectedVertex = hit.index
          ..bump();
        break;

      case _HitKind.edge:
        // Тянем за ребро -> сразу создаём вершину в этой точке и тащим её.
        final store = _selected;
        if (store?.zone == null) return;
        _pushUndo();
        store!.zone = store.zone!.insertedVertex(hit.index, _toNorm(hit.point!));
        _drag = _Drag.vertex;
        _dragStartZone = store.zone;
        _m
          ..selectedVertex = hit.index + 1
          ..hoverEdgePoint = null
          ..bump();
        break;

      case _HitKind.body:
        if (hit.storeId != _m.selectedId) {
          _m
            ..selectedId = hit.storeId
            ..selectedVertex = -1;
          _syncFields();
          setState(() {});
        }
        _pushUndo();
        _drag = _Drag.zone;
        _dragStartZone = _selected?.zone;
        _dragStartCanvas = local;
        break;

      case _HitKind.none:
        _startRect(local); // пустой пол — тянем рамку, как раньше
        break;
    }
  }

  void _startRect(Offset local) {
    if (_selected == null) {
      _toast('Сначала выберите магазин в списке справа');
      return;
    }
    _pushUndo();
    _drag = _Drag.rect;
    _dragStartCanvas = _applySnaps(local);
    final n = _toNorm(_dragStartCanvas);
    _m
      ..draftRect = Rect.fromPoints(n, n)
      ..bump();
  }

  void _onPanUpdate(Offset local) {
    if (_drag == _Drag.none) return;
    final store = _selected;
    if (store == null) return;

    switch (_drag) {
      case _Drag.rect:
        final end = _applySnaps(local, from: _dragStartCanvas);
        _m
          ..draftRect = Rect.fromPoints(_toNorm(_dragStartCanvas), _toNorm(end))
          ..bump();
        break;

      case _Drag.vertex:
        final base = _dragStartZone;
        if (base == null || _m.selectedVertex < 0 || store.zone == null) return;
        final count = store.zone!.points.length;
        final previous =
            store.zone!.points[(_m.selectedVertex - 1 + count) % count];
        store.zone = store.zone!.movedVertex(
          _m.selectedVertex,
          _vertexTarget(local,
              from: _toCanvas(previous), excludeId: store.id),
        );
        _m
          ..badEdges = PolygonMath.selfIntersections(store.zone!.points)
          ..bump();
        break;

      case _Drag.zone:
        final base = _dragStartZone;
        if (base == null) return;
        var delta = _toNorm(local) - _toNorm(_dragStartCanvas);
        if (_snapToGrid) {
          final moved = base.shifted(delta);
          final snappedTopLeft =
              _toNorm(_gridSnap(_toCanvas(moved.bounds.topLeft)));
          delta = delta + (snappedTopLeft - moved.bounds.topLeft);
        }
        store.zone = base.shifted(delta).clampedToUnit();
        _m.bump();
        break;

      // Вершина области подписи — тот же расчёт, что у вершины контура
      // зоны (_vertexTarget), только без магнита к соседям.
      case _Drag.labelVertex:
        final base = _labelPolyAtDragStart;
        if (base == null || _labelVertex < 0 || _labelVertex >= base.length) {
          return;
        }
        final previous =
            base[(_labelVertex - 1 + base.length) % base.length];
        final next = [...base];
        next[_labelVertex] = _vertexTarget(local,
            from: _toCanvas(previous), useMagnet: false);
        store.labelPolygon = next;
        _m.bump();
        break;

      case _Drag.labelMove:
        final base = _labelPolyAtDragStart;
        if (base == null) return;
        final delta = _toNorm(local) - _toNorm(_dragStartCanvas);
        store.labelPolygon =
            _clampLabelPolygon([for (final p in base) p + delta]);
        _m.bump();
        break;

      case _Drag.none:
        break;
    }
  }

  void _onPanEnd() {
    final store = _selected;
    final wasLabelDrag =
        _drag == _Drag.labelVertex || _drag == _Drag.labelMove;
    if (_drag == _Drag.rect && _m.draftRect != null && store != null) {
      final r = _m.draftRect!;
      final minW = 6 / _m.canvas.width / _scale;
      final minH = 6 / _m.canvas.height / _scale;
      if (r.width >= minW && r.height >= minH) {
        store.zone = ShopZone.fromRect(ShopZone.clampRectToUnit(r),
            entry: store.zone?.entry);
      } else if (_undo.isNotEmpty) {
        _undo.removeLast(); // клик без протяжки — снимок не нужен
      }
    }
    _drag = _Drag.none;
    _dragStartZone = null;
    _m.draftRect = null;
    _afterZoneChange();
    // Область подписи не часть контура: пишем сразу, минуя «Не сохранено».
    if (wasLabelDrag && store != null) _commitLabelPolygon(store);
  }

  // =========================================================================
  // Рисование контура
  // =========================================================================

  void _addDraftVertex(Offset local) {
    if (_selected == null) {
      _toast('Сначала выберите магазин в списке справа');
      return;
    }
    final draft = [..._m.draft];

    // Клик рядом с первой вершиной замыкает контур — это понятнее двойного
    // клика (а двойной клик в Flutter ещё и задерживает одиночный на ~300 мс).
    if (draft.length >= 3 &&
        (_toCanvas(draft.first) - local).distance <= _cx(_closeHit)) {
      _closeDraft();
      return;
    }

    final from = draft.isEmpty ? null : _toCanvas(draft.last);
    final snapped = _applySnaps(local, from: from, excludeId: _selected!.id);
    final n = _toNorm(snapped);
    draft.add(Offset(n.dx.clamp(0.0, 1.0), n.dy.clamp(0.0, 1.0)));
    _m
      ..draft = draft
      ..bump();
    setState(() {});
  }

  void _closeDraft() {
    final store = _selected;
    if (store == null || _m.draft.length < 3) return;
    _pushUndo();
    store.zone =
        ShopZone.polygon(_m.draft, entry: store.zone?.entry).clampedToUnit();
    _m
      ..draft = const []
      ..selectedVertex = -1;
    setState(() => _tool = _Tool.select);
    _afterZoneChange();
  }

  void _cancelDraft() {
    if (_m.draft.isEmpty) return;
    _m
      ..draft = const []
      ..bump();
    setState(() {});
  }

  void _removeLastDraftVertex() {
    if (_m.draft.isEmpty) return;
    _m
      ..draft = ([..._m.draft]..removeLast())
      ..bump();
    setState(() {});
  }

  void _deleteVertex(int index) {
    final store = _selected;
    if (store?.zone == null) return;
    final next = store!.zone!.removedVertex(index);
    if (next == null) {
      _toast('В контуре должно остаться минимум 3 вершины');
      return;
    }
    _pushUndo();
    store.zone = next;
    _m.selectedVertex = -1;
    _afterZoneChange();
  }

  /// Ставит якорь подписи и сразу пишет его в БД: якорь не часть контура,
  /// поэтому в «Не сохранено» и в undo он не попадает — ждать «Сохранить»
  /// было бы неоткуда видно. Инструмент остаётся активным: повторный клик
  /// просто переставляет точку.
  /// Вершины области подписи магазина в нормализованных координатах.
  ///
  /// Приоритет тот же, что у клиента: label_polygon -> label_rect (как
  /// 4 вершины) -> дефолт 80%×55% от габаритов зоны. Чем именно оказались
  /// точки, важно только отрисовке (пунктир и подпись «Дефолт»), поэтому
  /// здесь возвращаем просто контур.
  List<Offset>? _labelRegionOf(_ZoneRow row) {
    final poly = row.labelPolygon;
    if (poly != null && poly.length >= 3) return poly;
    final rect = row.labelRect ?? defaultLabelRect(row.zone);
    return rect == null ? null : rectToPoints(rect);
  }

  List<Offset> _labelCanvasPoints(List<Offset> pts) =>
      [for (final p in pts) _toCanvas(p)];

  /// Двигаем область целиком внутрь плана, не искажая форму — как
  /// ShopZone.clampedToUnit для контура зоны.
  List<Offset> _clampLabelPolygon(List<Offset> pts) {
    final b = PolygonMath.bounds(pts);
    var dx = 0.0, dy = 0.0;
    if (b.left < 0) dx = -b.left;
    if (b.right > 1) dx = 1 - b.right;
    if (b.top < 0) dy = -b.top;
    if (b.bottom > 1) dy = 1 - b.bottom;
    if (dx == 0 && dy == 0) return pts;
    return [for (final p in pts) p + Offset(dx, dy)];
  }

  /// Клик инструментом «Область подписи»: выбрать вершину, вставить её на
  /// ребре, удалить по Alt+клику — всё как у контура зоны.
  void _onLabelTap(Offset local) {
    final row = _selected;
    if (row == null) {
      _toast('Сначала выберите магазин');
      return;
    }
    final region = _labelRegionOf(row);

    // Ни области, ни зоны (от которой считается дефолт) — рисуем кликами.
    if (_m.labelDraft.isNotEmpty || region == null) {
      _addLabelDraftVertex(local);
      return;
    }

    final hit = _hitPolygon(_labelCanvasPoints(region), local, row.id);

    // Alt+клик по вершине удаляет её — ровно как у контура зоны.
    if (hit.kind == _HitKind.vertex &&
        HardwareKeyboard.instance.isAltPressed) {
      _deleteLabelVertex(hit.index);
      return;
    }
    if (hit.kind == _HitKind.vertex) {
      _m
        ..labelActiveVertex = hit.index
        ..bump();
      return;
    }
    if (hit.kind == _HitKind.edge && hit.point != null) {
      _editLabelPolygon(
          row, [...region]..insert(hit.index + 1, _toNorm(hit.point!)));
    }
  }

  /// Берёмся за область: вершина, ребро (сразу новая вершина) или тело.
  void _startLabelDrag(Offset local) {
    final row = _selected;
    if (row == null) {
      _toast('Сначала выберите магазин');
      return;
    }
    final region = _labelRegionOf(row);
    if (region == null) return;

    final hit = _hitPolygon(_labelCanvasPoints(region), local, row.id);
    if (hit.kind == _HitKind.none) return;

    _labelPolyBeforeEdit = row.labelPolygon;
    _labelRectBeforeEdit = row.labelRect;

    // Первое прикосновение превращает прямоугольник (или дефолт) в полигон:
    // миграция по явной правке, без фонового переписывания чужих строк.
    final points = [...region];

    switch (hit.kind) {
      case _HitKind.vertex:
        _labelVertex = hit.index;
        _drag = _Drag.labelVertex;
        break;
      case _HitKind.edge:
        points.insert(hit.index + 1, _toNorm(hit.point!));
        _labelVertex = hit.index + 1;
        _drag = _Drag.labelVertex;
        break;
      case _HitKind.body:
        _labelVertex = -1;
        _drag = _Drag.labelMove;
        break;
      case _HitKind.none:
        return;
    }

    row.labelPolygon = points;
    _labelPolyAtDragStart = List.of(points);
    _dragStartCanvas = local;
    _m
      ..labelActiveVertex = _labelVertex
      ..labelHoverEdge = null
      ..bump();
    setState(() {});
  }

  /// Удаление вершины правым кликом — дополнение к Alt+клику. У контура
  /// зоны правую кнопку не используем (в вебе всплывает меню браузера),
  /// здесь она удобна и перехватывается на уровне Listener.
  void _deleteLabelVertexAt(Offset local) {
    final row = _selected;
    final region = row == null ? null : _labelRegionOf(row);
    if (region == null) return;
    final hit = _hitPolygon(_labelCanvasPoints(region), local, row!.id);
    if (hit.kind == _HitKind.vertex) _deleteLabelVertex(hit.index);
  }

  void _deleteLabelVertex(int index) {
    final row = _selected;
    final region = row == null ? null : _labelRegionOf(row);
    if (region == null) return;
    if (region.length <= 3) {
      _toast('В области подписи должно остаться минимум 3 вершины');
      return;
    }
    _m
      ..labelActiveVertex = -1
      ..labelHoverVertex = -1
      ..labelHoverEdge = null;
    _editLabelPolygon(row!, [...region]..removeAt(index));
  }

  /// Правка области одним кликом (вставка/удаление вершины): меняем и
  /// сразу пишем.
  void _editLabelPolygon(_ZoneRow row, List<Offset> points) {
    if (points.length < 3) return;
    _labelPolyBeforeEdit = row.labelPolygon;
    _labelRectBeforeEdit = row.labelRect;
    row.labelPolygon = points;
    _m.bump();
    setState(() {});
    _commitLabelPolygon(row);
  }

  // --- черновик новой области (у магазина нет ни области, ни зоны) ------

  void _addLabelDraftVertex(Offset local) {
    final draft = [..._m.labelDraft];
    // Клик по первой вершине замыкает контур — как у инструмента «Контур».
    if (draft.length >= 3 &&
        (_toCanvas(draft.first) - local).distance <= _cx(_closeHit)) {
      _closeLabelDraft();
      return;
    }
    final from = draft.isEmpty ? null : _toCanvas(draft.last);
    draft.add(_vertexTarget(local, from: from, useMagnet: false));
    _m
      ..labelDraft = draft
      ..bump();
    setState(() {});
  }

  void _closeLabelDraft() {
    final row = _selected;
    if (row == null || _m.labelDraft.length < 3) return;
    final points = _clampLabelPolygon(_m.labelDraft);
    _m
      ..labelDraft = const []
      ..bump();
    _editLabelPolygon(row, points);
  }

  void _cancelLabelDraft() {
    if (_m.labelDraft.isEmpty) return;
    _m
      ..labelDraft = const []
      ..bump();
    setState(() {});
  }

  /// Пишем область подписи: полигон с точностью 4 знака, а label_rect
  /// обнуляем — полигон его заменяет (та самая миграция старых магазинов).
  Future<void> _commitLabelPolygon(_ZoneRow row) async {
    final pts = row.labelPolygon;
    if (pts == null || pts.length < 3) return;
    double r4(double v) => (v * 10000).round() / 10000;
    final rounded = [for (final p in pts) Offset(r4(p.dx), r4(p.dy))];

    row.labelPolygon = rounded;
    row.labelRect = null;
    _m.bump();
    setState(() {});

    final polyBefore = _labelPolyBeforeEdit;
    final rectBefore = _labelRectBeforeEdit;
    try {
      await _saveLabelFields(row, {
        'label_polygon': [
          for (final p in rounded) [p.dx, p.dy]
        ],
        'label_rect': null,
      });
    } catch (e) {
      debugPrint('❌ _commitLabelPolygon(${row.id}): $e');
      row.labelPolygon = polyBefore;
      row.labelRect = rectBefore;
      _m.bump();
      if (mounted) setState(() {});
      _toast('Не удалось сохранить область подписи: $e', error: true);
    }
  }

  void _syncAngleField(double? angle) {
    final text = angle == null ? '' : _fmtAngle(angle);
    if (_angleCtrl.text != text) _angleCtrl.text = text;
  }

  /// Сброс: область, прямоугольник и угол в null — подпись снова
  /// размещается сама.
  Future<void> _clearLabelPlacement() async {
    final row = _selected;
    if (row == null ||
        (row.labelPolygon == null &&
            row.labelRect == null &&
            row.labelAngle == null)) {
      return;
    }
    final polyBefore = row.labelPolygon;
    final rectBefore = row.labelRect;
    final angleBefore = row.labelAngle;
    row.labelPolygon = null;
    row.labelRect = null;
    row.labelAngle = null;
    _syncAngleField(null);
    _m.bump();
    setState(() {});
    try {
      await _saveLabelFields(row, {
        'label_polygon': null,
        'label_rect': null,
        'label_angle': null,
      });
      _toast('Область подписи сброшена — положение снова автоматическое');
    } catch (e) {
      debugPrint('❌ _clearLabelPlacement(${row.id}): $e');
      row.labelPolygon = polyBefore;
      row.labelRect = rectBefore;
      row.labelAngle = angleBefore;
      _syncAngleField(angleBefore);
      _m.bump();
      if (mounted) setState(() {});
      _toast('Не удалось сбросить область: $e', error: true);
    }
  }

  /// Разбирает поле «Угол поворота». Пусто -> null (как раньше,
  /// автоматически). Значение зажимаем в -180..180.
  Future<void> _applyAngleField() async {
    final row = _selected;
    if (row == null) return;
    final text = _angleCtrl.text.trim().replaceAll(',', '.');
    if (text.isEmpty) {
      await _applyLabelAngle(row, null);
      return;
    }
    final parsed = double.tryParse(text);
    if (parsed == null) {
      _toast('Угол — число от -180 до 180', error: true);
      _syncFields();
      return;
    }
    // Храним с той же точностью, с какой показываем — до десятых.
    final clamped = parsed.clamp(-180.0, 180.0).toDouble();
    await _applyLabelAngle(row, (clamped * 10).round() / 10);
  }

  Future<void> _clearLabelAngle() async {
    final row = _selected;
    if (row == null || row.labelAngle == null) return;
    await _applyLabelAngle(row, null);
  }

  Future<void> _applyLabelAngle(_ZoneRow row, double? angle) async {
    if (row.labelAngle == angle) {
      _syncFields();
      return;
    }
    final previous = row.labelAngle;
    row.labelAngle = angle;
    _m.bump();
    setState(() {});
    try {
      await _saveLabelFields(row, {'label_angle': angle});
    } catch (e) {
      debugPrint('❌ _applyLabelAngle(${row.id}): $e');
      row.labelAngle = previous;
      _m.bump();
      if (mounted) setState(() {});
      _toast('Не удалось сохранить угол: $e', error: true);
    }
    // Нормализуем текст: 200 после зажима стало 180, пустое — пустым.
    final normalized =
        row.labelAngle == null ? '' : _fmtAngle(row.labelAngle!);
    if (_angleCtrl.text != normalized) _angleCtrl.text = normalized;
  }

  void _setEntry(Offset local) {
    final store = _selected;
    if (store?.zone == null) {
      _toast('Сначала нарисуйте зону');
      return;
    }
    // Дверь всегда на стене: цепляем точку к ближайшему ребру.
    final hit = PolygonMath.closestOnBoundary(
        store!.zone!.canvasPoints(_m.canvas), local);
    _pushUndo();
    store.zone = store.zone!.withEntry(_toNorm(hit.point));
    setState(() => _tool = _Tool.select);
    _afterZoneChange();
  }

  // =========================================================================
  // Зум
  // =========================================================================

  void _zoomAt(Offset canvasPoint, double factor) {
    final m = _view.value;
    final s = m.getMaxScaleOnAxis();
    final next = (s * factor).clamp(1.0, 12.0);
    if ((next - s).abs() < 0.0001) return;
    final t = Offset(m.storage[12], m.storage[13]);
    final screen = t + canvasPoint * s;
    final t2 = screen - canvasPoint * next;
    _view.value = _clampMatrix(Matrix4.identity()
      ..translate(t2.dx, t2.dy)
      ..scale(next));
  }

  Matrix4 _clampMatrix(Matrix4 m) {
    if (_m.canvas == Size.zero) return m;
    final s = m.getMaxScaleOnAxis();
    final tx = m.storage[12].clamp(_m.canvas.width * (1 - s), 0.0);
    final ty = m.storage[13].clamp(_m.canvas.height * (1 - s), 0.0);
    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(s);
  }

  void _resetZoom() => _view.value = Matrix4.identity();

  void _focusSelected() {
    final zone = _m.selectedZone;
    if (zone == null || _m.canvas == Size.zero) return;
    final b = zone.bounds;
    final target =
        math.min(8.0, math.max(1.0, 0.3 / math.max(b.width, b.height)));
    final center = _toCanvas(b.center);
    _view.value = _clampMatrix(Matrix4.identity()
      ..translate(_m.canvas.width / 2 - center.dx * target,
          _m.canvas.height / 2 - center.dy * target)
      ..scale(target));
  }

  // =========================================================================
  // Клавиатура
  // =========================================================================

  /// В текстовом поле (поиск, координаты, угол) пробел — это пробел, а не
  /// «взять план в руку», и V/R/P/E/L/H — буквы, а не смена инструмента.
  /// Фокус внутри полей — единственный случай, когда редактор отдаёт
  /// клавиши: иначе набрать в поле что-либо было бы нельзя.
  bool get _typingInField =>
      _xFocus.hasFocus ||
      _yFocus.hasFocus ||
      _wFocus.hasFocus ||
      _hFocus.hasFocus ||
      _angleFocus.hasFocus ||
      _searchFocus.hasFocus;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_typingInField) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent && !_spaceHeld) setState(() => _spaceHeld = true);
      if (event is KeyUpEvent && _spaceHeld) setState(() => _spaceHeld = false);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (_m.labelDraft.isNotEmpty) {
        _cancelLabelDraft();
      } else if (_m.draft.isNotEmpty) {
        _cancelDraft();
      } else {
        setState(() => _tool = _Tool.select);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _m.labelDraft.isNotEmpty ? _closeLabelDraft() : _closeDraft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace && _m.draft.isNotEmpty) {
      _removeLastDraftVertex();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      shift ? _doRedo() : _doUndo();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyY) {
      _doRedo();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyS) {
      _saveAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      _m.selectedVertex >= 0 ? _deleteVertex(_m.selectedVertex) : _clearZone();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _step(shift ? -1 : 1);
      return KeyEventResult.handled;
    }

    final tools = {
      LogicalKeyboardKey.keyV: _Tool.select,
      LogicalKeyboardKey.keyR: _Tool.rect,
      LogicalKeyboardKey.keyP: _Tool.polygon,
      LogicalKeyboardKey.keyE: _Tool.entry,
      LogicalKeyboardKey.keyL: _Tool.labelAnchor,
      LogicalKeyboardKey.keyH: _Tool.pan,
    };
    final tool = tools[key];
    if (tool != null && !ctrl) {
      setState(() => _tool = tool);
      return KeyEventResult.handled;
    }

    final arrows = {
      LogicalKeyboardKey.arrowLeft: Offset(-1, 0),
      LogicalKeyboardKey.arrowRight: Offset(1, 0),
      LogicalKeyboardKey.arrowUp: Offset(0, -1),
      LogicalKeyboardKey.arrowDown: Offset(0, 1),
    };
    final dir = arrows[key];
    if (dir != null) {
      _nudge(dir, shift ? 10 : 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Шаг — ровно один пиксель исходного изображения плана.
  void _nudge(Offset dir, double multiplier) {
    final store = _selected;
    if (store?.zone == null || _imageSize == null) return;
    final step = Offset(
      dir.dx * multiplier / _imageSize!.width,
      dir.dy * multiplier / _imageSize!.height,
    );
    _pushUndo();
    if (_m.selectedVertex >= 0 &&
        _m.selectedVertex < store!.zone!.points.length) {
      final p = store.zone!.points[_m.selectedVertex] + step;
      store.zone = store.zone!.movedVertex(
        _m.selectedVertex,
        Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0)),
      );
    } else {
      store!.zone = store.zone!.shifted(step).clampedToUnit();
    }
    _afterZoneChange();
  }

  void _clearZone() {
    final store = _selected;
    if (store?.zone == null) return;
    _pushUndo();
    store!.zone = null;
    _m.selectedVertex = -1;
    _afterZoneChange();
  }

  void _step(int delta) {
    final list = _filtered;
    if (list.isEmpty) return;
    var index = list.indexWhere((s) => s.id == _m.selectedId);
    if (index < 0) index = 0;
    var next = (index + delta) % list.length;
    if (next < 0) next += list.length;
    _m
      ..selectedId = list[next].id
      ..selectedVertex = -1
      ..draft = const [];
    _afterZoneChange();
    _focusSelected();
  }

  void _nextUnplaced() {
    final list = _filtered;
    if (list.isEmpty) return;
    final index = list.indexWhere((s) => s.id == _m.selectedId);
    for (var i = 1; i <= list.length; i++) {
      final candidate = list[(index + i) % list.length];
      if (!candidate.isPlaced) {
        _m
          ..selectedId = candidate.id
          ..selectedVertex = -1
          ..draft = const [];
        _resetZoom();
        _afterZoneChange();
        return;
      }
    }
    _toast('Все магазины размечены');
  }

  // =========================================================================
  // Сохранение
  // =========================================================================

  Future<void> _saveRow(_ZoneRow row) async {
    final payload =
        row.zone == null ? ShopZone.emptyDbPayload() : row.zone!.toDb();
    await _sb.from('shops').update(payload).eq('firestore_id', row.id);
    AuditLogger.log(
      action: 'update',
      collection: 'shops',
      docId: row.id,
      changes: payload,
    );
    row.saved = row.zone;
  }

  /// Ручная расстановка подписи (label_x/label_y/label_angle) пишется
  /// отдельным update'ом: ShopZone.toDb() об этих полях не знает, поэтому
  /// сохранение зоны их не затирает.
  Future<void> _saveLabelFields(
      _ZoneRow row, Map<String, dynamic> payload) async {
    await _sb.from('shops').update(payload).eq('firestore_id', row.id);
    AuditLogger.log(
      action: 'update',
      collection: 'shops',
      docId: row.id,
      changes: payload,
    );
  }

  /// Самопересечение ломает хит-тест у клиента (лучевой алгоритм посчитает
  /// часть «бабочки» внешней), поэтому спрашиваем подтверждение.
  Future<bool> _confirmBadGeometry(List<_ZoneRow> rows) async {
    final bad =
        rows.where((r) => r.zone != null && r.zone!.isSelfIntersecting).toList();
    if (bad.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Контур пересекает сам себя'),
        content: Text(
          'Проблемные магазины: ${bad.map((r) => r.name).join(', ')}.\n\n'
          'У клиента такая зона будет нажиматься неправильно: часть площади '
          'окажется «снаружи». Лучше поправить вершины.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Вернуться и поправить')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Всё равно сохранить')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _saveCurrent() async {
    final row = _selected;
    if (row == null) return;
    if (!await _confirmBadGeometry([row])) return;
    setState(() => _saving = true);
    try {
      await _saveRow(row);
      _toast('Зона «${row.name}» сохранена');
    } catch (e) {
      debugPrint('❌ _saveCurrent: $e');
      _toast('Ошибка сохранения: $e', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _saveAll() async {
    final dirty = _stores.where((s) => s.isDirty).toList();
    if (dirty.isEmpty) {
      _toast('Нет несохранённых изменений');
      return;
    }
    if (!await _confirmBadGeometry(dirty)) return;
    setState(() => _saving = true);
    var ok = 0;
    for (final row in dirty) {
      try {
        await _saveRow(row);
        ok++;
      } catch (e) {
        debugPrint('❌ _saveAll(${row.id}): $e');
      }
    }
    if (mounted) {
      setState(() => _saving = false);
      _toast(ok == dirty.length
          ? 'Сохранено зон: $ok'
          : 'Сохранено $ok из ${dirty.length}. Подробности в консоли.');
    }
  }

  Future<bool?> _confirmDiscard() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Несохранённые изменения'),
          content: Text('Изменено зон: $_dirtyCount. Они будут потеряны.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Остаться')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Продолжить без сохранения')),
          ],
        ),
      );

  Future<void> _copyZoneTo() async {
    final source = _selected;
    if (source?.zone == null) {
      _toast('Сначала нарисуйте зону-образец');
      return;
    }
    final targets = <String>{};
    var keepPosition = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Скопировать контур «${source!.name}»'),
          content: SizedBox(
            width: 440,
            height: 440,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: keepPosition,
                  onChanged: (v) => setDialog(() => keepPosition = v),
                  title: const Text('Сохранить положение магазина'),
                  subtitle: const Text(
                      'Контур переносится по центру существующей зоны. Выключите, чтобы скопировать и координаты.'),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: _stores
                        .where((s) => s.id != source.id)
                        .map((s) => CheckboxListTile(
                              dense: true,
                              value: targets.contains(s.id),
                              title: Text(s.name),
                              subtitle:
                                  Text(s.isPlaced ? 'зона есть' : 'не размечен'),
                              onChanged: (v) => setDialog(() => v == true
                                  ? targets.add(s.id)
                                  : targets.remove(s.id)),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (targets.isEmpty) return;
                _pushUndo();
                for (final s in _stores) {
                  if (!targets.contains(s.id)) continue;
                  if (keepPosition && s.zone != null) {
                    final delta =
                        s.zone!.bounds.center - source.zone!.bounds.center;
                    s.zone = source.zone!.shifted(delta).clampedToUnit();
                  } else {
                    s.zone = source.zone;
                  }
                }
                _afterZoneChange();
                _toast(
                    'Применено к ${targets.length} магазинам. Не забудьте сохранить.');
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // =========================================================================
  // UI
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (_loadingMalls) return const Center(child: CircularProgressIndicator());
    if (_malls.isEmpty) {
      return const _Placeholder(
        icon: Icons.location_city_rounded,
        title: 'Нет торговых центров',
        subtitle: 'Добавьте ТЦ и загрузите план этажа в поле map_image_url.',
      );
    }

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      // Пробел отпускают уже вне редактора (Cmd+Tab, клик в другое поле) —
      // KeyUp тогда не приходит, и план навсегда остаётся «в руке».
      onFocusChange: (has) {
        if (!has && _spaceHeld) setState(() => _spaceHeld = false);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;
          return Column(
            children: [
              _buildToolbar(compact: constraints.maxWidth < 1400),
              _buildHintBar(),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildCanvasArea()),
                          const VerticalDivider(width: 1),
                          SizedBox(width: 360, child: _buildPanel()),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            SizedBox(height: 520, child: _buildCanvasArea()),
                            const Divider(height: 1),
                            SizedBox(height: 620, child: _buildPanel()),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- тулбар ---
  //
  // Компактная раскладка: инструменты только иконками, редкие переключатели
  // (сетка/привязка/магнит/предпросмотр) спрятаны в меню «Вид». Поэтому
  // ничего не вылезает за правый край даже на ноутбучном экране.
  Widget _buildToolbar({required bool compact}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          if (!compact)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Text('Редактор зон',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          SizedBox(
            width: compact ? 170 : 220,
            child: DropdownButtonFormField<String>(
              value: _mall?.id,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: _malls
                  .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          m.mapImageUrl == null
                              ? '${m.name} (нет плана)'
                              : m.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (id) =>
                  _selectMall(_malls.firstWhere((m) => m.id == id)),
            ),
          ),
          const SizedBox(width: 10),
          _toolButton(_Tool.select, Icons.near_me_outlined, 'Выделение (V)'),
          _toolButton(_Tool.rect, Icons.crop_square_rounded, 'Прямоугольник (R)'),
          _toolButton(_Tool.polygon, Icons.polyline_rounded, 'Контур (P)'),
          _toolButton(_Tool.entry, Icons.sensor_door_outlined, 'Вход (E)'),
          _toolButton(
              _Tool.labelAnchor, Icons.text_fields, 'Область подписи (L)'),
          _toolButton(_Tool.pan, Icons.back_hand_outlined, 'Рука (H / пробел)'),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Отменить (Ctrl+Z)',
            onPressed: _undo.isEmpty ? null : _doUndo,
            icon: const Icon(Icons.undo_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Вернуть (Ctrl+Shift+Z)',
            onPressed: _redo.isEmpty ? null : _doRedo,
            icon: const Icon(Icons.redo_rounded, size: 20),
          ),
          _buildViewMenu(),
          const Spacer(),
          if (_dirtyCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.orange.withOpacity(0.15),
                side: BorderSide.none,
                label: Text('Не сохранено: $_dirtyCount',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveAll,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(compact ? 'Сохранить' : 'Сохранить всё'),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(_Tool tool, IconData icon, String tooltip) {
    final active = _tool == tool && !(_spaceHeld && tool != _Tool.pan);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (_m.draft.isNotEmpty && tool != _Tool.polygon) _cancelDraft();
            // Клик по кнопке уводит фокус на неё, и _onKey больше не
            // вызывается: пробел перестаёт панорамировать, пока не щёлкнешь
            // по плану. Возвращаем фокус редактору сразу.
            _focus.requestFocus();
            setState(() => _tool = tool);
          },
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: active
                  ? AdminColors.primary.withOpacity(0.12)
                  : AdminColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: active ? AdminColors.primary : Colors.transparent),
            ),
            child: Icon(icon,
                size: 19,
                color: active ? AdminColors.primary : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }

  Widget _buildViewMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Вид',
      icon: const Icon(Icons.tune_rounded, size: 20),
      onSelected: (value) {
        setState(() {
          switch (value) {
            case 'grid':
              _m.showGrid = !_m.showGrid;
              break;
            case 'snap':
              _snapToGrid = !_snapToGrid;
              break;
            case 'magnet':
              _magnet = !_magnet;
              break;
            case 'g10':
              _m.gridDivisions = 10;
              break;
            case 'g20':
              _m.gridDivisions = 20;
              break;
            case 'g40':
              _m.gridDivisions = 40;
              break;
            case 'p_off':
              _m.preview = _PreviewMode.off;
              break;
            case 'p_idle':
              _m.preview = _PreviewMode.idle;
              break;
            case 'p_hover':
              _m.preview = _PreviewMode.hover;
              break;
            case 'p_visited':
              _m.preview = _PreviewMode.visited;
              break;
          }
        });
        _m.bump();
      },
      itemBuilder: (ctx) => [
        CheckedPopupMenuItem(
            value: 'grid', checked: _m.showGrid, child: const Text('Сетка')),
        CheckedPopupMenuItem(
            value: 'snap',
            checked: _snapToGrid,
            child: const Text('Привязка к сетке')),
        CheckedPopupMenuItem(
            value: 'magnet',
            checked: _magnet,
            child: const Text('Магнит к соседям')),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
            value: 'g10',
            checked: _m.gridDivisions == 10,
            child: const Text('Сетка 10×10')),
        CheckedPopupMenuItem(
            value: 'g20',
            checked: _m.gridDivisions == 20,
            child: const Text('Сетка 20×20')),
        CheckedPopupMenuItem(
            value: 'g40',
            checked: _m.gridDivisions == 40,
            child: const Text('Сетка 40×40')),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
            value: 'p_off',
            checked: _m.preview == _PreviewMode.off,
            child: const Text('Режим правки')),
        CheckedPopupMenuItem(
            value: 'p_idle',
            checked: _m.preview == _PreviewMode.idle,
            child: const Text('Предпросмотр: обычный')),
        CheckedPopupMenuItem(
            value: 'p_hover',
            checked: _m.preview == _PreviewMode.hover,
            child: const Text('Предпросмотр: наведение')),
        CheckedPopupMenuItem(
            value: 'p_visited',
            checked: _m.preview == _PreviewMode.visited,
            child: const Text('Предпросмотр: посещён')),
      ],
    );
  }

  Widget _buildHintBar() {
    String hint;
    switch (_tool) {
      case _Tool.polygon:
        hint = _m.draft.isEmpty
            ? 'Кликайте по углам магазина · Shift — ровные углы · Esc — отмена'
            : 'Вершин: ${_m.draft.length} · клик по первой точке или Enter — замкнуть · Backspace — убрать последнюю';
        break;
      case _Tool.entry:
        hint = 'Кликните на стену магазина — туда придёт маршрут';
        break;
      case _Tool.labelAnchor:
        hint = _m.labelDraft.isEmpty
            ? 'Тяните вершины области подписи · клик по ребру — новая вершина · Alt+клик или правый клик — удалить · сохраняется сразу'
            : 'Вершин: ${_m.labelDraft.length} · клик по первой точке или Enter — замкнуть область';
        break;
      case _Tool.rect:
        hint = 'Протяните рамку по витрине магазина';
        break;
      case _Tool.pan:
        hint = 'Тяните план мышью · колесо — зум';
        break;
      case _Tool.select:
        hint =
            'Тяните вершины · клик по ребру — новая вершина · Alt+клик по вершине — удалить · стрелки — сдвиг на 1 px';
        break;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: AdminColors.surfaceVariant,
      child:
          Text(hint, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
    );
  }

  // --- холст ---

  Widget _buildCanvasArea() {
    if (_mall?.mapImageUrl == null) {
      return const _Placeholder(
        icon: Icons.image_not_supported_outlined,
        title: 'У этого ТЦ нет плана этажа',
        subtitle:
            'Загрузите PNG в Storage и впишите ссылку в malls.map_image_url.',
      );
    }
    if (_imageError != null) {
      return _Placeholder(
        icon: Icons.broken_image_outlined,
        title: 'План не загрузился',
        subtitle: 'Проверьте, что ссылка публичная.',
        action: TextButton(
          onPressed: () {
            setState(() => _imageError = null);
            _attachImage(_mall!.mapImageUrl);
          },
          child: const Text('Повторить'),
        ),
      );
    }

    return Container(
      color: const Color(0xFFF2F4F7),
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          var width = constraints.maxWidth;
          if (constraints.maxHeight.isFinite &&
              width / _aspect > constraints.maxHeight) {
            width = constraints.maxHeight * _aspect;
          }
          final canvas = Size(width, width / _aspect);
          _m.canvas = canvas; // производное от layout, setState не нужен

          return Center(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: canvas.width,
                    height: canvas.height,
                    child: _buildViewer(canvas),
                  ),
                ),
                if (!_mapReady)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white70,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Загружаем план этажа…'),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(right: 10, bottom: 10, child: _buildZoomControls()),
                Positioned(left: 10, bottom: 10, child: _buildScaleBadge()),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildViewer(Size canvas) {
    final panMode = _tool == _Tool.pan || _spaceHeld;

    return InteractiveViewer(
      transformationController: _view,
      minScale: 1,
      maxScale: 12,
      // План двигает только «рука». В остальных режимах все перетаскивания
      // достаются слою рисования, поэтому арбитраж жестов не нужен.
      panEnabled: panMode,
      scaleEnabled: panMode,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: canvas.width,
        height: canvas.height,
        child: Listener(
          // Listener внутри child: localPosition уже в координатах холста,
          // и он первым регистрируется в PointerSignalResolver.
          // _onTapUp обнулён, пока держат пробел или выбрана «Рука», —
          // фокус возвращаем здесь, иначе после панорамы мышью редактор
          // остаётся без клавиатуры.
          onPointerDown: (event) {
            _focus.requestFocus();
            if (_tool == _Tool.labelAnchor &&
                event.buttons == kSecondaryButton) {
              _deleteLabelVertexAt(event.localPosition);
            }
          },
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _zoomAt(event.localPosition,
                  event.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15);
            }
          },
          child: MouseRegion(
            cursor: _cursor,
            onHover: (e) => _onHover(e.localPosition),
            onExit: (_) {
              _m
                ..hoverId = null
                ..hoverVertex = -1
                ..hoverEdgePoint = null
                ..cursor = null
                ..bump();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: panMode ? null : (d) => _onTapUp(d.localPosition),
              onPanStart: panMode ? null : (d) => _onPanStart(d.localPosition),
              onPanUpdate: panMode ? null : (d) => _onPanUpdate(d.localPosition),
              onPanEnd: panMode ? null : (_) => _onPanEnd(),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      _mall!.mapImageUrl!,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  // RepaintBoundary + repaint-нотификатор: во время драга
                  // перерисовывается только этот слой, без rebuild дерева.
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: ZonesPainter(
                          model: _m,
                          labelTool: _tool == _Tool.labelAnchor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    Widget button(IconData icon, String tip, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Material(
            color: Colors.white,
            elevation: 2,
            borderRadius: BorderRadius.circular(10),
            child: Tooltip(
              message: tip,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child:
                    SizedBox(width: 36, height: 36, child: Icon(icon, size: 18)),
              ),
            ),
          ),
        );
    final center = Offset(_m.canvas.width / 2, _m.canvas.height / 2);
    return Column(
      children: [
        button(Icons.add, 'Приблизить', () => _zoomAt(center, 1.3)),
        button(Icons.remove, 'Отдалить', () => _zoomAt(center, 1 / 1.3)),
        button(Icons.crop_free_rounded, 'Весь план', _resetZoom),
        button(Icons.center_focus_strong_rounded, 'К выбранной зоне',
            _focusSelected),
      ],
    );
  }

  Widget _buildScaleBadge() {
    final planPx = (_imageSize != null && _m.canvas.width > 0)
        ? _imageSize!.width / (_m.canvas.width * _scale)
        : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${(_scale * 100).round()}%  ·  1 px экрана ≈ ${planPx.toStringAsFixed(1)} px плана',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  // --- правая панель ---

  Widget _buildPanel() {
    return Container(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Инспектор занимает столько, сколько нужно, но не больше 55%
            // панели и с прокруткой. Раньше он уходил в Column с
            // неограниченной высотой: координаты + кнопки + секции подписи
            // перестали влезать на невысоком окне, и Column переполнялся
            // (RenderFlex overflowed by 349 pixels on the bottom).
            ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: constraints.maxHeight * 0.55),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: _buildInspector(),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                focusNode: _searchFocus,
                decoration: const InputDecoration(
                  hintText: 'Поиск магазина',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(child: _buildStoreList()),
          ],
        ),
      ),
    );
  }

  Widget _buildInspector() {
    final row = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row?.name ?? 'Магазин не выбран',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Предыдущий (Shift+Tab)',
              onPressed: () => _step(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: 'Следующий (Tab)',
              onPressed: () => _step(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (row != null)
          Text(row.id,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 10),

        // Живые цифры обновляются по нотификатору холста, без setState.
        AnimatedBuilder(
          animation: _m,
          builder: (context, _) => _buildZoneStats(row),
        ),

        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _saveCurrent,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Сохранить зону'),
            ),
            OutlinedButton.icon(
              onPressed: _nextUnplaced,
              icon: const Icon(Icons.skip_next_rounded, size: 16),
              label: const Text('Следующий без зоны'),
            ),
            IconButton(
              tooltip: 'Скопировать контур другим магазинам',
              onPressed: _copyZoneTo,
              icon: const Icon(Icons.copy_all_rounded),
            ),
            IconButton(
              tooltip: 'Заменить контур прямоугольником по габаритам',
              onPressed: row?.zone == null
                  ? null
                  : () {
                      _pushUndo();
                      row!.zone = ShopZone.fromRect(row.zone!.bounds,
                          entry: row.zone!.entry);
                      _afterZoneChange();
                    },
              icon: const Icon(Icons.crop_square_rounded),
            ),
            IconButton(
              tooltip: 'Удалить зону (Delete)',
              onPressed: row?.zone == null ? null : _clearZone,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        if (row != null) _buildLabelRectSection(row),
        if (row != null) _buildLabelAngleSection(row),
      ],
    );
  }

  /// Ручной якорь подписи. Отдельная секция, а не строка в _buildZoneStats:
  /// якорь можно поставить и магазину без зоны, а статистика в этом случае
  /// вообще не показывается.
  Widget _buildLabelRectSection(_ZoneRow row) {
    final poly = row.labelPolygon;
    final rect = row.labelRect;
    final legacyAnchor = row.labelOverride;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 22),
        Row(
          children: [
            const Icon(Icons.format_shapes_rounded,
                size: 16, color: kLabelAnchorColor),
            const SizedBox(width: 6),
            const Text('Область подписи',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        _statLine(
          'Форма',
          poly != null
              ? 'Полигон, ${poly.length} вершин'
              : rect != null
                  ? 'Прямоугольник'
                  : 'Дефолт',
        ),
        if (poly == null && rect != null)
          _statLine(
            'Размер',
            'w ${rect.width.toStringAsFixed(3)} · '
                'h ${rect.height.toStringAsFixed(3)}',
          ),
        // label_x/label_y больше не пишутся, но у старых магазинов они
        // лежат в БД и всё ещё работают у клиента, пока нет рамки.
        if (legacyAnchor != null)
          _statLine(
            'Старый якорь',
            '${legacyAnchor.dx.toStringAsFixed(3)}, '
                '${legacyAnchor.dy.toStringAsFixed(3)}',
          ),
        TextButton(
          onPressed: (_saving ||
                  (poly == null && rect == null && row.labelAngle == null))
              ? null
              : _clearLabelPlacement,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Сбросить', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 6),
        Text(
          'Инструмент L — задайте область подписи. Точки тянутся, '
          'добавляются на рёбрах, удаляются правым кликом. Сохраняется '
          'автоматически.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  /// Угол подписи. Пишется в БД по Enter/уходу из поля — тем же update'ом,
  /// что якорь, и так же минует undo.
  Widget _buildLabelAngleSection(_ZoneRow row) {
    final angle = row.labelAngle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 22),
        Row(
          children: [
            const Icon(Icons.rotate_right_rounded,
                size: 16, color: kLabelAnchorColor),
            const SizedBox(width: 6),
            const Text('Угол поворота',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: _angleCtrl,
                focusNode: _angleFocus,
                // Вводить можно всегда: у полигона значение не влияет на
                // отрисовку, но сохраняется — пригодится, если область
                // снова станет прямоугольной.
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Градусы',
                  hintText: '0',
                  suffixText: '°',
                  isDense: true,
                  filled: true,
                  fillColor: AdminColors.surfaceVariant,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onSubmitted: (_) => _applyAngleField(),
                onEditingComplete: _applyAngleField,
              ),
            ),
            const SizedBox(width: 10),
            // Та же рамка, что рисуется на плане, — видно наклон до клика.
            _AnglePreview(angle: angle ?? 0),
          ],
        ),
        const SizedBox(height: 4),
        _statLine(
          'Сохранено',
          angle == null ? 'не задано' : '${_fmtAngle(angle)}°',
        ),
        TextButton(
          onPressed: (angle == null || _saving) ? null : _clearLabelAngle,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Сбросить угол', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 6),
        Text(
          'От -180 до 180, по часовой стрелке, с точностью до десятых. '
          'Применяется к любой области подписи — полигону, прямоугольнику '
          'или дефолтной рамке.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildZoneStats(_ZoneRow? row) {
    final zone = row?.zone;
    if (zone == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AdminColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Зона не размечена. Протяните рамку инструментом «Прямоугольник» '
          'или обведите магазин инструментом «Контур».',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      );
    }

    final b = zone.bounds;
    final px = _imageSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (zone.isSelfIntersecting)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Контур пересекает сам себя — проблемные рёбра подсвечены красным.',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                  ),
                ),
              ],
            ),
          ),
        if (zone.isRectangle) ...[
          Row(children: [
            Expanded(child: _coordField('Центр X', _xCtrl, _xFocus)),
            const SizedBox(width: 8),
            Expanded(child: _coordField('Центр Y', _yCtrl, _yFocus)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _coordField('Ширина', _wCtrl, _wFocus)),
            const SizedBox(width: 8),
            Expanded(child: _coordField('Высота', _hCtrl, _hFocus)),
          ]),
          const SizedBox(height: 10),
        ],
        _statLine('Вершин', '${zone.points.length}'),
        _statLine(
          'Габариты',
          px == null
              ? '${b.width.toStringAsFixed(3)} × ${b.height.toStringAsFixed(3)}'
              : '${(b.width * px.width).round()} × ${(b.height * px.height).round()} px плана',
        ),
        _statLine('Площадь', '${(zone.area * 100).toStringAsFixed(2)} % плана'),
        _statLine(
          'Вход',
          zone.entry == null
              ? 'не задан — маршрут в центр'
              : '${zone.entry!.dx.toStringAsFixed(3)}, ${zone.entry!.dy.toStringAsFixed(3)}',
        ),
        if (zone.entry != null)
          TextButton(
            onPressed: () {
              _pushUndo();
              _selected!.zone = zone.withEntry(null);
              _afterZoneChange();
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Сбросить вход', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _statLine(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
            Expanded(
              child: Text(value,
                  style:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _coordField(String label, TextEditingController c, FocusNode f) =>
      TextField(
        controller: c,
        focusNode: f,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: AdminColors.surfaceVariant,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        onSubmitted: (_) => _applyFields(),
        onEditingComplete: _applyFields,
      );

  Widget _buildStoreList() {
    if (_loadingStores) return const Center(child: CircularProgressIndicator());
    final list = _filtered;
    if (list.isEmpty) {
      return const _Placeholder(
        icon: Icons.storefront_outlined,
        title: 'Магазинов нет',
        subtitle: 'Проверьте поле mall_id у магазинов.',
      );
    }
    final placed = _stores.where((s) => s.isPlaced).length;
    final polygons =
        _stores.where((s) => s.zone != null && !s.zone!.isRectangle).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            'Размечено $placed из ${_stores.length} · контуров: $polygons',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final row = list[index];
              final selected = row.id == _m.selectedId;
              return InkWell(
                onTap: () {
                  if (_m.draft.isNotEmpty) _cancelDraft();
                  _m
                    ..selectedId = row.id
                    ..selectedVertex = -1;
                  _afterZoneChange();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  color: selected
                      ? AdminColors.primary.withOpacity(0.08)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: row.isDirty
                              ? Colors.orange
                              : row.isPlaced
                                  ? Colors.green
                                  : Colors.grey.shade300,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? AdminColors.primary : null,
                          ),
                        ),
                      ),
                      if (row.zone != null)
                        Icon(
                          row.zone!.isRectangle
                              ? Icons.crop_square_rounded
                              : Icons.polyline_rounded,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                      if (row.zone?.entry != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.sensor_door_outlined,
                            size: 14, color: Colors.grey.shade500),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Отрисовка
// ===========================================================================

class ZonesPainter extends CustomPainter {
  final _CanvasModel model;

  /// Активен инструмент «Рамка подписи» — показываем рамку и ручки.
  final bool labelTool;

  ZonesPainter({required this.model, this.labelTool = false})
      : super(repaint: model);

  double get _s => model.scale;

  /// Всё, что должно иметь постоянный размер на экране, делим на масштаб.
  double _px(double screenPx) => screenPx / _s;

  @override
  void paint(Canvas canvas, Size size) {
    if (model.showGrid && model.preview == _PreviewMode.off) {
      _paintGrid(canvas, size);
    }

    for (final row in model.stores) {
      final zone = row.zone;
      if (zone == null) continue;
      _paintZone(canvas, size, zone, row, row.id == model.selectedId,
          row.id == model.hoverId);
    }

    final selectedZone = model.selectedZone;
    if (selectedZone != null && model.preview == _PreviewMode.off) {
      _paintHandles(canvas, size, selectedZone);
    }

    // Область подписи — только у выбранного магазина и только в своём
    // инструменте: 90 оранжевых контуров на плане читать невозможно.
    if (labelTool && model.preview == _PreviewMode.off) {
      for (final row in model.stores) {
        if (row.id != model.selectedId) continue;
        _paintLabelRegion(canvas, size, row);
      }
    }

    if (model.draft.isNotEmpty) _paintDraft(canvas, size);
    if (model.draftRect != null) _paintDraftRect(canvas, size);
    if (model.entrance != null) {
      _paintEntrance(canvas, _toCanvas(model.entrance!, size));
    }
  }

  Offset _toCanvas(Offset n, Size size) =>
      Offset(n.dx * size.width, n.dy * size.height);

  void _paintGrid(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = Colors.black.withOpacity(0.09)
      ..strokeWidth = _px(0.6);
    final bold = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..strokeWidth = _px(1.1);
    for (var i = 1; i < model.gridDivisions; i++) {
      final paint = i % 5 == 0 ? bold : thin;
      final x = size.width * i / model.gridDivisions;
      final y = size.height * i / model.gridDivisions;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintZone(Canvas canvas, Size size, ShopZone zone, _ZoneRow row,
      bool selected, bool hovered) {
    final path = zone.toPath(size);

    late Color fill;
    late Color stroke;
    var strokeWidth = _px(1.3);

    if (model.preview != _PreviewMode.off) {
      switch (model.preview) {
        case _PreviewMode.hover:
          fill = ClientZoneStyle.hover;
          stroke = ClientZoneStyle.border;
          strokeWidth = _px(2);
          break;
        case _PreviewMode.visited:
          fill = ClientZoneStyle.visited;
          stroke = Colors.transparent;
          break;
        default:
          fill = selected ? ClientZoneStyle.selected : ClientZoneStyle.idle;
          stroke = selected ? ClientZoneStyle.border : Colors.transparent;
          strokeWidth = _px(2);
      }
    } else {
      fill = selected
          ? AdminColors.primary.withOpacity(0.26)
          : hovered
              ? AdminColors.primary.withOpacity(0.15)
              : Colors.black.withOpacity(0.07);
      stroke = selected
          ? AdminColors.primary
          : hovered
              ? AdminColors.primary.withOpacity(0.7)
              : Colors.black.withOpacity(0.35);
      strokeWidth = _px(selected ? 2 : 1.2);
    }

    canvas.drawPath(path, Paint()..color = fill);
    if (stroke != Colors.transparent) {
      canvas.drawPath(
        path,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }

    // Самопересечения — только у выделенной зоны, красным.
    if (selected && model.badEdges.isNotEmpty) {
      final pts = zone.canvasPoints(size);
      final bad = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = _px(2.5);
      for (final i in model.badEdges) {
        if (i >= pts.length) continue;
        canvas.drawLine(pts[i], pts[(i + 1) % pts.length], bad);
      }
    }

    // Подпись — без своих порогов и украшений: ровно то, что нарисует
    // клиент (см. _paintLabel ниже).
    _paintLabel(canvas, size, row, zone);

    if (zone.entry != null) {
      _paintEntry(canvas, _toCanvas(zone.entry!, size), selected);
    }
  }

  /// Габариты области подписи — тем же приоритетом, что у клиента
  /// (_MapPainter._effectiveLabelRect): полигон -> прямоугольник ->
  /// дефолт 80%×55% от габаритов зоны.
  Rect? _effectiveLabelRect(_ZoneRow row, ShopZone zone) {
    final poly = row.labelPolygon;
    if (poly != null && poly.length >= 3) return PolygonMath.bounds(poly);
    return row.labelRect ?? defaultLabelRect(zone);
  }

  /// Область подписи выбранного магазина: контур, заливка и ручки вершин —
  /// теми же ручками, что у контура зоны, только оранжевыми.
  void _paintLabelRegion(Canvas canvas, Size size, _ZoneRow row) {
    // Рисуем новую область кликами — показываем черновик.
    if (model.labelDraft.isNotEmpty) {
      final cursor = model.cursor;
      _paintDraftPolygon(
        canvas,
        [for (final p in model.labelDraft) _toCanvas(p, size)],
        cursor == null ? null : _toCanvas(cursor, size),
        kLabelAnchorColor,
      );
      return;
    }

    final poly = row.labelPolygon;
    final custom = poly != null && poly.length >= 3;

    List<Offset> points;
    String? tag;
    if (custom) {
      points = poly;
    } else {
      final rect = row.labelRect ?? defaultLabelRect(row.zone);
      if (rect == null) return;
      points = rectToPoints(rect);
      tag = row.labelRect != null ? 'Прямоугольник' : 'Дефолт';
    }

    final pts = [for (final p in points) _toCanvas(p, size)];
    final path = Path()..addPolygon(pts, true);

    canvas.drawPath(path, Paint()..color = kLabelAnchorColor.withOpacity(0.1));

    if (custom) {
      canvas.drawPath(
        path,
        Paint()
          ..color = kLabelAnchorColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _px(2),
      );
    } else {
      // Подмена — пунктиром и бледнее: в БД её ещё нет.
      final pale = kLabelAnchorColor.withOpacity(0.4);
      for (var i = 0; i < pts.length; i++) {
        _paintDashedLine(canvas, pts[i], pts[(i + 1) % pts.length],
            color: pale);
      }
      final caption = TextPainter(
        text: TextSpan(
          text: tag,
          style: TextStyle(
            fontSize: _px(10),
            fontWeight: FontWeight.w700,
            color: pale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final b = PolygonMath.bounds(pts);
      caption.paint(canvas, b.topLeft - Offset(0, caption.height + _px(2)));
    }

    _paintVertexHandles(
      canvas,
      pts,
      color: kLabelAnchorColor,
      activeIndex: model.labelActiveVertex,
      hoverIndex: model.labelHoverVertex,
      edgePlus: model.labelHoverEdge,
    );
  }

  /// Копия _buildLabelPainter из клиента.
  TextPainter _buildLabelPainter(
      String name, double fontSize, double maxWidth) {
    final visible = fontSize * _s;
    final weight = visible >= 18
        ? FontWeight.w400
        : visible >= 13
            ? FontWeight.w500
            : FontWeight.w600;
    return TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: const Color(0xFF14171C),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  // Копия _paintLabel из клиента
  // (offline_deals_app/lib/map/mall_map_widget.dart), ветка с областью.
  // Если меняешь логику подписи — обнови в обоих файлах, иначе предпросмотр
  // в админке разойдётся с тем, что видит покупатель.
  //
  // Отличия только в единицах: у клиента кегль делится на scale вручную,
  // здесь то же самое делает _px(). Якорную ветку клиента не копируем —
  // она срабатывает лишь у зоны с вырожденными габаритами.
  void _paintLabel(Canvas canvas, Size size, _ZoneRow row, ShopZone zone) {
    final labelRect = _effectiveLabelRect(row, zone);
    if (labelRect == null || labelRect.width <= 0 || labelRect.height <= 0) {
      return;
    }

    final rectPx = Rect.fromLTWH(
      labelRect.left * size.width,
      labelRect.top * size.height,
      labelRect.width * size.width,
      labelRect.height * size.height,
    );
    // Константы отступа и кегля ниже (8/9/16/24/32/5/3) подбирались на
    // холсте iPhone шириной ~377px. Приводим их к фактической ширине
    // холста: иначе один и тот же магазин переносится по-разному на
    // телефоне, планшете и в предпросмотре админки, где холст втрое шире.
    final canvasRatio = size.width / 377.0;

    // Отступ внутри области: 8 приведённых пикселей, но не больше 8% ширины.
    final pad = math.min(_px(8 * canvasRatio), rectPx.width * 0.08);
    final innerW = math.max(1.0, rectPx.width - pad);
    final innerH = math.max(1.0, rectPx.height - pad);

    // Узкая высокая область -> текст идёт вдоль неё, повёрнутый на 90°.
    // Нарисованному вручную контуру ориентацию не навязываем.
    // Автоматическая вертикаль применяется только если оператор не задал
    // угол. Явный угол — воля оператора, он сильнее эвристики формы.
    final hasAngle = (row.labelAngle ?? 0) != 0;
    final vertical = !hasAngle &&
        row.labelPolygon == null &&
        rectPx.height > rectPx.width * 1.3;

    // Длина строки идёт по одной оси области, толщина блока — по другой.
    final runPx = vertical ? innerH : innerW;
    final thinPx = vertical ? innerW : innerH;

    final isDefaultRect = row.labelPolygon == null && row.labelRect == null;

    // Потолок кегля зависит от зума: _s 1 -> 9px, 2 -> 12px, 6+ -> 24px.
    final zoomCap = math.min(24.0, math.max(9.0, 9.0 + (_s - 1.0) * 3.0)) *
        canvasRatio /
        _s;
    final maxFont = math.min(zoomCap, 32.0 * canvasRatio / _s);
    final minFont = (isDefaultRect ? 3.0 : 5.0) * canvasRatio / _s;
    var fontSize = math.min(16.0 * canvasRatio / _s, maxFont);

    // Растём, пока влезает.
    while (true) {
      final next = fontSize / 0.9;
      if (next > maxFont) break;
      final probe = _buildLabelPainter(row.name, next, runPx);
      final fits = probe.height <= thinPx && !probe.didExceedMaxLines;
      probe.dispose();
      if (!fits) break;
      fontSize = next;
    }

    // Затем обычная усадка, если стартовый кегль не влез.
    var painter = _buildLabelPainter(row.name, fontSize, runPx);
    while (painter.height > thinPx && fontSize > minFont) {
      painter.dispose();
      fontSize *= 0.9;
      painter = _buildLabelPainter(row.name, fontSize, runPx);
    }
    // Как и у клиента, повторно height не проверяем: не влезло — рисуем
    // как есть, зона без названия хуже мелкого названия.

    final center = rectPx.center;
    final rad = (row.labelAngle ?? 0) * math.pi / 180;
    final topLeft = Offset(-painter.width / 2, -painter.height / 2);

    if (vertical) {
      // Форма сама диктует ориентацию, label_angle здесь не применяется.
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(math.pi / 2);
      painter.paint(canvas, topLeft);
      canvas.restore();
    } else if (rad != 0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rad);
      painter.paint(canvas, topLeft);
      canvas.restore();
    } else {
      painter.paint(canvas, center + topLeft);
    }
    painter.dispose();
  }

  void _paintHandles(Canvas canvas, Size size, ShopZone zone) =>
      _paintVertexHandles(
        canvas,
        zone.canvasPoints(size),
        color: AdminColors.primary,
        activeIndex: model.selectedVertex,
        hoverIndex: model.hoverVertex,
        edgePlus: model.hoverEdgePoint,
      );

  /// Ручки вершин и «плюс» на ребре под курсором.
  ///
  /// Общие для контура зоны (синие) и области подписи (оранжевые):
  /// размеры, толщины и поведение одни и те же, меняется только цвет.
  void _paintVertexHandles(
    Canvas canvas,
    List<Offset> pts, {
    required Color color,
    int activeIndex = -1,
    int hoverIndex = -1,
    Offset? edgePlus,
  }) {
    final fill = Paint()..color = Colors.white;
    final active = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(1.6);

    for (var i = 0; i < pts.length; i++) {
      final isActive = i == activeIndex;
      final r = _px(isActive || i == hoverIndex ? 6.5 : 5.5);
      canvas.drawCircle(pts[i], r, isActive ? active : fill);
      canvas.drawCircle(pts[i], r, stroke);
    }

    // «Плюс» для вставки вершины — только на ребре под курсором:
    // иначе 30 вершин превращаются в 30 плюсиков и кашу.
    final plus = edgePlus;
    if (plus != null) {
      final r = _px(7);
      canvas.drawCircle(plus, r, Paint()..color = Colors.white);
      canvas.drawCircle(plus, r, stroke);
      final arm = _px(3.5);
      final bar = Paint()
        ..color = color
        ..strokeWidth = _px(1.6);
      canvas.drawLine(plus - Offset(arm, 0), plus + Offset(arm, 0), bar);
      canvas.drawLine(plus - Offset(0, arm), plus + Offset(0, arm), bar);
    }
  }

  void _paintDraft(Canvas canvas, Size size) {
    final cursor = model.cursor;
    _paintDraftPolygon(
      canvas,
      [for (final p in model.draft) _toCanvas(p, size)],
      cursor == null ? null : _toCanvas(cursor, size),
      AdminColors.primary,
    );
  }

  /// Рисуемый кликами контур: заливка, ломаная, пунктир к курсору и
  /// вершины. Общий для контура зоны и для области подписи.
  void _paintDraftPolygon(
      Canvas canvas, List<Offset> pts, Offset? cursorPx, Color color) {
    if (pts.isEmpty) return;

    if (pts.length >= 3) {
      canvas.drawPath(
        Path()..addPolygon(pts, true),
        Paint()..color = color.withOpacity(0.12),
      );
    }

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px(2);
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);

    // Пунктир от последней вершины к курсору.
    if (cursorPx != null) {
      _paintDashedLine(canvas, pts.last, cursorPx,
          color: color.withOpacity(0.8));
    }

    // Первая вершина крупнее: по ней кликают, чтобы замкнуть контур.
    for (var i = 0; i < pts.length; i++) {
      final r = _px(i == 0 ? 7 : 5);
      canvas.drawCircle(pts[i], r, Paint()..color = Colors.white);
      canvas.drawCircle(
        pts[i],
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _px(1.8),
      );
    }
  }

  void _paintDashedLine(Canvas canvas, Offset a, Offset b, {Color? color}) {
    final total = (b - a).distance;
    if (total < 0.01) return;
    final paint = Paint()
      ..color = color ?? AdminColors.primary.withOpacity(0.8)
      ..strokeWidth = _px(1.6);
    final dir = (b - a) / total;
    final dash = _px(6), gap = _px(4);
    var travelled = 0.0;
    while (travelled < total) {
      final end = math.min(travelled + dash, total);
      canvas.drawLine(a + dir * travelled, a + dir * end, paint);
      travelled = end + gap;
    }
  }

  void _paintDraftRect(Canvas canvas, Size size) {
    final r = model.draftRect!;
    final rect = Rect.fromLTRB(r.left * size.width, r.top * size.height,
        r.right * size.width, r.bottom * size.height);
    canvas.drawRect(
        rect, Paint()..color = AdminColors.primary.withOpacity(0.18));
    canvas.drawRect(
      rect,
      Paint()
        ..color = AdminColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = _px(1.5),
    );
  }

  void _paintEntry(Canvas canvas, Offset p, bool selected) {
    final r = _px(selected ? 6 : 4.5);
    canvas.drawCircle(p, r + _px(2), Paint()..color = Colors.white);
    canvas.drawCircle(p, r, Paint()..color = const Color(0xFF16A34A));
  }

  void _paintEntrance(Canvas canvas, Offset p) {
    final r = _px(8);
    canvas.drawCircle(p, r + _px(3), Paint()..color = Colors.white);
    canvas.drawCircle(p, r, Paint()..color = const Color(0xFF1E5AFF));
    final painter = TextPainter(
      text: TextSpan(
        text: 'Вход в ТЦ',
        style: TextStyle(
          fontSize: _px(10),
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1E5AFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, p + Offset(r + _px(4), -painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant ZonesPainter old) => true;
}

// ===========================================================================

/// Наклонный прямоугольник рядом с полем угла: мгновенная обратная связь,
/// не требующая искать магазин на плане.
class _AnglePreview extends StatelessWidget {
  final double angle;
  const _AnglePreview({required this.angle});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AdminColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Transform.rotate(
            angle: angle * math.pi / 180,
            child: Container(
              width: 30,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: kLabelAnchorColor, width: 1.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
}

class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  const _Placeholder({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
        // Прокрутка вместо Padding с тем же отступом: заглушка живёт и в
        // Expanded правой панели, где высоты на иконку + два текста + кнопку
        // не всегда хватает (RenderFlex overflowed by 7.0 pixels).
        // Пока содержимое влезает, SingleChildScrollView равен ему по высоте,
        // и Center центрирует блок ровно как раньше.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(title,
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (action != null) ...[const SizedBox(height: 8), action!],
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// ПОДКЛЮЧЕНИЕ: без изменений — _pages[14] = const ZoneEditorScreen(),
// пункт «Редактор зон» в Drawer только для _isAggregator.
// ---------------------------------------------------------------------------