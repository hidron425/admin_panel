// lib/map/shop_zone.dart
//
// Общая модель зоны магазина и вся полигональная математика.
// Один и тот же файл используют клиент (MallMapWidget) и админка
// (ZoneEditorScreen) — положите его в общий пакет или скопируйте в оба
// приложения, но не расходитесь реализациями: формула «что считается
// внутри зоны» должна быть ровно одна.
//
// Внутреннее представление ВСЕГДА полигон. Прямоугольник из старых полей
// map_x/map_y/map_width/map_height — это просто полигон из 4 вершин.
// Благодаря этому у клиента остаётся один путь отрисовки и один хит-тест.

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Зона магазина на плане этажа. Все координаты нормализованы 0..1
/// относительно изображения плана.
class ShopZone {
  /// Вершины контура по порядку обхода. Замыкающая вершина не хранится.
  final List<Offset> points;

  /// Точка входа (дверь) на границе контура. null -> берём «визуальный центр».
  final Offset? entry;

  /// Якорь подписи, выставленный руками в админке (shops.label_x/label_y).
  /// null -> положение подбирается автоматически, как раньше.
  ///
  /// Правки контура (withPoints/movedVertex/shifted/...) якорь НЕ переносят:
  /// он живёт в БД и в редакторе зон, а клиент зону не правит.
  final Offset? labelOverride;

  /// Угол подписи в градусах по часовой стрелке (shops.label_angle).
  /// null или 0 -> подпись ставится как раньше (горизонтально, а в узкой
  /// высокой зоне — автоматически вдоль неё).
  final double? labelAngle;

  /// Прямоугольник подписи, выставленный руками в админке
  /// (shops.label_rect = [x, y, w, h], нормализованные 0..1, от левого
  /// верхнего угла). Задан -> текст живёт внутри него и больше не
  /// подбирает себе место сам. null -> всё как раньше, по якорю.
  final Rect? labelRect;

  /// Произвольная область подписи (shops.label_polygon = [[x,y],...],
  /// нормализованные 0..1, как map_polygon). Старше прямоугольника:
  /// задана -> подпись считается по её габаритам.
  final List<Offset>? labelPolygon;

  ShopZone._(this.points, this.entry, this.labelOverride, this.labelAngle,
      this.labelRect, this.labelPolygon);

  factory ShopZone.polygon(List<Offset> pts,
      {Offset? entry,
      Offset? labelOverride,
      double? labelAngle,
      Rect? labelRect,
      List<Offset>? labelPolygon}) {
    assert(pts.length >= 3, 'Полигон не может иметь меньше 3 вершин');
    return ShopZone._(List.unmodifiable(pts), entry, labelOverride, labelAngle,
        labelRect, labelPolygon);
  }

  factory ShopZone.fromRect(Rect r,
          {Offset? entry,
          Offset? labelOverride,
          double? labelAngle,
          Rect? labelRect,
          List<Offset>? labelPolygon}) =>
      ShopZone._(
        List.unmodifiable([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]),
        entry,
        labelOverride,
        labelAngle,
        labelRect,
        labelPolygon,
      );

  // --- кэш тяжёлых вычислений ---
  Rect? _bounds;
  Offset? _centroid;
  Offset? _anchor;
  double? _area;

  // =========================================================================
  // БД
  // =========================================================================

  /// Читает зону из строки таблицы shops.
  /// Приоритет: map_polygon -> старые прямоугольные поля -> null.
  static ShopZone? fromDb(Map<String, dynamic> row) {
    final entry = _readEntry(row);
    final labelOverride = readLabelOverride(row);
    final labelAngle = readLabelAngle(row);
    final labelRect = readLabelRect(row);
    final labelPolygon = readLabelPolygon(row);

    final raw = row['map_polygon'];
    final pts = _parsePoints(raw);
    if (pts != null && pts.length >= 3) {
      return ShopZone.polygon(pts,
          entry: entry,
          labelOverride: labelOverride,
          labelAngle: labelAngle,
          labelRect: labelRect,
          labelPolygon: labelPolygon);
    }

    final x = row['map_x'] as num?;
    final y = row['map_y'] as num?;
    final w = row['map_width'] as num?;
    final h = row['map_height'] as num?;
    if (x == null || y == null || w == null || h == null) return null;
    if (w <= 0 || h <= 0) return null;
    return ShopZone.fromRect(
      clampRectToUnit(Rect.fromCenter(
        center: Offset(x.toDouble(), y.toDouble()),
        width: w.toDouble(),
        height: h.toDouble(),
      )),
      entry: entry,
      labelOverride: labelOverride,
      labelAngle: labelAngle,
      labelRect: labelRect,
      labelPolygon: labelPolygon,
    );
  }

  static Offset? _readEntry(Map<String, dynamic> row) {
    final ex = row['entry_x'] as num?;
    final ey = row['entry_y'] as num?;
    if (ex == null || ey == null) return null;
    return Offset(ex.toDouble(), ey.toDouble());
  }

  /// Ручной якорь подписи из строки shops. Нужен ровно один раз — когда
  /// заданы ОБА поля; одна координата без второй смысла не имеет.
  /// Публичный: тем же чтением пользуются места, где зона собирается не из
  /// сырой строки (фолбэк на прямоугольник в клиенте, редактор в админке).
  static Offset? readLabelOverride(Map<String, dynamic> row) {
    final lx = row['label_x'] as num?;
    final ly = row['label_y'] as num?;
    if (lx == null || ly == null) return null;
    return Offset(lx.toDouble(), ly.toDouble());
  }

  /// Ручной угол подписи из строки shops, в градусах.
  static double? readLabelAngle(Map<String, dynamic> row) =>
      (row['label_angle'] as num?)?.toDouble();

  /// Ручной прямоугольник подписи из строки shops.
  static Rect? readLabelRect(Map<String, dynamic> row) =>
      parseLabelRect(row['label_rect']);

  /// Произвольная область подписи из строки shops. Меньше трёх вершин —
  /// это не контур, возвращаем null и падаем на прямоугольник.
  static List<Offset>? readLabelPolygon(Map<String, dynamic> row) {
    final raw = row['label_polygon'];
    if (raw is! List) return null;
    final out = <Offset>[];
    for (final v in raw) {
      if (v is List && v.length >= 2) {
        final x = (v[0] as num?)?.toDouble();
        final y = (v[1] as num?)?.toDouble();
        if (x != null && y != null) out.add(Offset(x, y));
      }
    }
    return out.length >= 3 ? out : null;
  }

  /// [x, y, w, h] -> Rect. Нулевые и отрицательные размеры отбрасываем:
  /// такой прямоугольник нечем заполнить, и клиент должен вернуться к
  /// автоматическому размещению, а не нарисовать подпись в точке.
  static Rect? parseLabelRect(dynamic raw) {
    if (raw is! List || raw.length < 4) return null;
    final v = <double>[];
    for (final item in raw) {
      if (item is! num) return null;
      v.add(item.toDouble());
    }
    if (v[2] <= 0 || v[3] <= 0) return null;
    return Rect.fromLTWH(v[0], v[1], v[2], v[3]);
  }

  /// Понимает оба формата: [[x,y], ...] и [{"x":..,"y":..}, ...].
  static List<Offset>? _parsePoints(dynamic raw) {
    if (raw is! List) return null;
    final out = <Offset>[];
    for (final item in raw) {
      if (item is List && item.length >= 2) {
        final x = item[0], y = item[1];
        if (x is num && y is num) out.add(Offset(x.toDouble(), y.toDouble()));
      } else if (item is Map) {
        final x = item['x'], y = item['y'];
        if (x is num && y is num) out.add(Offset(x.toDouble(), y.toDouble()));
      }
    }
    return out.isEmpty ? null : out;
  }

  /// Пишем И полигон, И его bounding box в старые поля.
  ///
  /// Двойная запись — не грязь, а осознанный шаг: приложение на iOS
  /// обновляется не мгновенно, и старые сборки продолжат читать
  /// map_x/map_width. Прямоугольник чуть щедрее реального контура,
  /// но это намного лучше, чем пустая карта.
  Map<String, dynamic> toDb({int decimals = 4}) {
    final r = rounded(decimals);
    final b = r.bounds;
    return {
      'map_polygon': r.points.map((p) => [p.dx, p.dy]).toList(),
      'map_x': b.center.dx,
      'map_y': b.center.dy,
      'map_width': b.width,
      'map_height': b.height,
      'entry_x': r.entry?.dx,
      'entry_y': r.entry?.dy,
    };
  }

  /// Полная очистка зоны.
  static Map<String, dynamic> emptyDbPayload() => {
        'map_polygon': null,
        'map_x': null,
        'map_y': null,
        'map_width': null,
        'map_height': null,
        'entry_x': null,
        'entry_y': null,
      };

  // =========================================================================
  // Геометрия
  // =========================================================================

  Rect get bounds => _bounds ??= PolygonMath.bounds(points);

  double get area => _area ??= PolygonMath.area(points);

  /// Центр масс. Для L/U-образных зон может оказаться СНАРУЖИ контура.
  Offset get centroid => _centroid ??= PolygonMath.centroid(points);

  /// Точка, куда ставим подпись.
  ///
  /// Ручной якорь из админки важнее расчётного: оператор видел план целиком
  /// и поставил подпись туда, где она читается. Если якоря нет — центр масс,
  /// когда он внутри контура, иначе «полюс недоступности».
  Offset get labelAnchor {
    if (labelOverride != null) return labelOverride!;
    if (_anchor != null) return _anchor!;
    final c = centroid;
    _anchor = PolygonMath.contains(points, c)
        ? c
        : PolygonMath.poleOfInaccessibility(points);
    return _anchor!;
  }

  /// Куда ведёт маршрут: к двери, если она задана, иначе к центру зоны.
  Offset get destination => entry ?? labelAnchor;

  bool get isRectangle {
    if (points.length != 4) return false;
    const e = 1e-6;
    return (points[0].dy - points[1].dy).abs() < e &&
        (points[2].dy - points[3].dy).abs() < e &&
        (points[0].dx - points[3].dx).abs() < e &&
        (points[1].dx - points[2].dx).abs() < e;
  }

  bool get isSelfIntersecting => !PolygonMath.isSimple(points);

  bool contains(Offset p, {double tolerance = 1e-9}) =>
      PolygonMath.contains(points, p, edgeTolerance: tolerance);

  Path toPath(Size canvas) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * canvas.width, points[i].dy * canvas.height);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  List<Offset> canvasPoints(Size canvas) => [
        for (final p in points)
          Offset(p.dx * canvas.width, p.dy * canvas.height),
      ];

  // =========================================================================
  // Правки (всегда возвращают новый объект — так снимки undo безопасны)
  // =========================================================================

  ShopZone withPoints(List<Offset> pts) => ShopZone.polygon(pts, entry: entry);

  ShopZone withEntry(Offset? e) => ShopZone.polygon(points, entry: e);

  /// Снимает ручную расстановку подписи (якорь, угол, прямоугольник).
  ///
  /// Нужна редактору зон: там эти поля живут в строке списка магазинов, а
  /// не в модели — иначе после «Очистить якорь» остались бы два источника
  /// правды, и зона продолжала бы отвечать старым значением.
  ShopZone withoutLabelPlacement() =>
      ShopZone.polygon(points, entry: entry);

  ShopZone movedVertex(int index, Offset p) {
    final pts = [...points]..[index] = p;
    return ShopZone.polygon(pts, entry: entry);
  }

  ShopZone insertedVertex(int afterIndex, Offset p) {
    final pts = [...points]..insert(afterIndex + 1, p);
    return ShopZone.polygon(pts, entry: entry);
  }

  ShopZone? removedVertex(int index) {
    if (points.length <= 3) return null;
    final pts = [...points]..removeAt(index);
    return ShopZone.polygon(pts, entry: entry);
  }

  ShopZone shifted(Offset delta) => ShopZone.polygon(
        [for (final p in points) p + delta],
        entry: entry == null ? null : entry! + delta,
      );

  /// Двигает весь контур внутрь плана целиком, не искажая форму.
  ShopZone clampedToUnit() {
    final b = bounds;
    var dx = 0.0, dy = 0.0;
    if (b.left < 0) dx = -b.left;
    if (b.right > 1) dx = 1 - b.right;
    if (b.top < 0) dy = -b.top;
    if (b.bottom > 1) dy = 1 - b.bottom;
    if (dx == 0 && dy == 0) {
      // Контур шире плана — зажимаем каждую вершину по отдельности.
      if (b.width <= 1 && b.height <= 1) return this;
      return ShopZone.polygon(
        [
          for (final p in points)
            Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0))
        ],
        entry: entry == null
            ? null
            : Offset(entry!.dx.clamp(0.0, 1.0), entry!.dy.clamp(0.0, 1.0)),
      );
    }
    return shifted(Offset(dx, dy));
  }

  ShopZone rounded(int decimals) {
    final f = math.pow(10, decimals).toDouble();
    double r(double v) => (v * f).round() / f;
    return ShopZone.polygon(
      [for (final p in points) Offset(r(p.dx), r(p.dy))],
      entry: entry == null ? null : Offset(r(entry!.dx), r(entry!.dy)),
    );
  }

  /// Сравнение по сохраняемой точности: иначе шум double помечает
  /// нетронутые зоны как изменённые.
  bool sameAs(ShopZone? other, {int decimals = 4}) {
    if (other == null) return false;
    final a = rounded(decimals), b = other.rounded(decimals);
    if (a.points.length != b.points.length) return false;
    for (var i = 0; i < a.points.length; i++) {
      if (a.points[i] != b.points[i]) return false;
    }
    return a.entry == b.entry;
  }

  static Rect clampRectToUnit(Rect r) {
    final w = r.width.clamp(0.0, 1.0);
    final h = r.height.clamp(0.0, 1.0);
    return Rect.fromLTWH(
      r.left.clamp(0.0, 1.0 - w),
      r.top.clamp(0.0, 1.0 - h),
      w,
      h,
    );
  }
}

// ===========================================================================
// Математика
// ===========================================================================

class PolygonMath {
  const PolygonMath._();

  static Rect bounds(List<Offset> p) {
    var minX = p.first.dx, maxX = p.first.dx;
    var minY = p.first.dy, maxY = p.first.dy;
    for (final v in p) {
      if (v.dx < minX) minX = v.dx;
      if (v.dx > maxX) maxX = v.dx;
      if (v.dy < minY) minY = v.dy;
      if (v.dy > maxY) maxY = v.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static double signedArea(List<Offset> p) {
    var sum = 0.0;
    for (var i = 0, j = p.length - 1; i < p.length; j = i++) {
      sum += (p[j].dx * p[i].dy) - (p[i].dx * p[j].dy);
    }
    return sum / 2;
  }

  static double area(List<Offset> p) => signedArea(p).abs();

  /// Центр масс многоугольника (НЕ среднее арифметическое вершин —
  /// оно смещается туда, где вершины гуще).
  static Offset centroid(List<Offset> p) {
    final a = signedArea(p);
    if (a.abs() < 1e-12) {
      // Вырожденный контур — среднее по вершинам хотя бы не даст NaN.
      var sx = 0.0, sy = 0.0;
      for (final v in p) {
        sx += v.dx;
        sy += v.dy;
      }
      return Offset(sx / p.length, sy / p.length);
    }
    var cx = 0.0, cy = 0.0;
    for (var i = 0, j = p.length - 1; i < p.length; j = i++) {
      final cross = (p[j].dx * p[i].dy) - (p[i].dx * p[j].dy);
      cx += (p[j].dx + p[i].dx) * cross;
      cy += (p[j].dy + p[i].dy) * cross;
    }
    return Offset(cx / (6 * a), cy / (6 * a));
  }

  /// Лучевой алгоритм. Точка ровно на ребре считается внутри: на общей
  /// стене двух магазинов лучше отдать клик кому-то, чем никому.
  static bool contains(List<Offset> poly, Offset q, {double edgeTolerance = 1e-9}) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if (edgeTolerance > 0 && distanceToSegment(q, a, b) <= edgeTolerance) {
        return true;
      }
      final crosses = (a.dy > q.dy) != (b.dy > q.dy);
      if (crosses) {
        final x = (b.dx - a.dx) * (q.dy - a.dy) / (b.dy - a.dy) + a.dx;
        if (q.dx < x) inside = !inside;
      }
    }
    return inside;
  }

  static Offset closestPointOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSq < 1e-18) return a;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    return Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  }

  static double distanceToSegment(Offset p, Offset a, Offset b) =>
      (p - closestPointOnSegment(p, a, b)).distance;

  /// Ближайшая точка на контуре + индекс ребра, которому она принадлежит.
  static ({Offset point, int edgeIndex, double distance}) closestOnBoundary(
    List<Offset> poly,
    Offset p,
  ) {
    var best = poly.first;
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final c = closestPointOnSegment(p, a, b);
      final d = (p - c).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = c;
        bestIndex = i;
      }
    }
    return (point: best, edgeIndex: bestIndex, distance: bestDistance);
  }

  static double distanceToBoundary(List<Offset> poly, Offset p) =>
      closestOnBoundary(poly, p).distance;

  /// «Полюс недоступности»: самая глубокая точка внутри контура.
  /// Для L/U-образных зон это единственный разумный якорь подписи.
  /// Сетка + пара уточняющих проходов — точности с избытком для надписи.
  static Offset poleOfInaccessibility(List<Offset> poly,
      {int grid = 16, int passes = 3}) {
    var rect = bounds(poly);
    var best = centroid(poly);
    var bestDepth = -1.0;

    for (var pass = 0; pass < passes; pass++) {
      for (var i = 0; i <= grid; i++) {
        for (var j = 0; j <= grid; j++) {
          final p = Offset(
            rect.left + rect.width * i / grid,
            rect.top + rect.height * j / grid,
          );
          if (!contains(poly, p)) continue;
          final depth = distanceToBoundary(poly, p);
          if (depth > bestDepth) {
            bestDepth = depth;
            best = p;
          }
        }
      }
      rect = Rect.fromCenter(
        center: best,
        width: rect.width * 2 / grid,
        height: rect.height * 2 / grid,
      );
    }
    return bestDepth < 0 ? centroid(poly) : best;
  }

  /// Пересекаются ли отрезки (общие концы не считаются пересечением).
  static bool segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    double cross(Offset o, Offset p, Offset q) =>
        (p.dx - o.dx) * (q.dy - o.dy) - (p.dy - o.dy) * (q.dx - o.dx);

    final d1 = cross(c, d, a);
    final d2 = cross(c, d, b);
    final d3 = cross(a, b, c);
    final d4 = cross(a, b, d);

    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    return false;
  }

  /// Простой (не самопересекающийся) ли контур.
  /// O(n²), но n <= 60 — это десятки операций.
  static bool isSimple(List<Offset> poly) => selfIntersections(poly).isEmpty;

  /// Индексы рёбер, которые пересекают друг друга — чтобы подсветить их в UI.
  static Set<int> selfIntersections(List<Offset> poly) {
    final bad = <int>{};
    final n = poly.length;
    if (n < 4) return bad;
    for (var i = 0; i < n; i++) {
      final a1 = poly[i], a2 = poly[(i + 1) % n];
      for (var j = i + 1; j < n; j++) {
        // Соседние рёбра имеют общую вершину — пропускаем.
        if (j == i || (j + 1) % n == i || (i + 1) % n == j) continue;
        final b1 = poly[j], b2 = poly[(j + 1) % n];
        if (segmentsIntersect(a1, a2, b1, b2)) {
          bad.add(i);
          bad.add(j);
        }
      }
    }
    return bad;
  }

  /// Привязка к углам 0/45/90° относительно опорной точки (Shift при рисовании).
  static Offset orthoSnap(Offset from, Offset to) {
    final d = to - from;
    final angle = math.atan2(d.dy, d.dx);
    final step = math.pi / 4;
    final snapped = (angle / step).round() * step;
    final length = d.distance;
    return from + Offset(math.cos(snapped) * length, math.sin(snapped) * length);
  }
}