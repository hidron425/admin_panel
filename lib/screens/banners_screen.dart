import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;

// ----------------------------------------------------------------------
// ЭКРАН УПРАВЛЕНИЯ БАННЕРАМИ (с редактором изображений)
// ----------------------------------------------------------------------
class BannersScreen extends StatefulWidget {
  const BannersScreen({Key? key}) : super(key: key);

  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends State<BannersScreen> {
  final _firestore = FirebaseFirestore.instance;

  // ==================== ДИАЛОГ ДОБАВЛЕНИЯ БАННЕРА ====================
  Future<void> _addBanner() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final discountCtrl = TextEditingController();
    final imageUrlCtrl = TextEditingController();

    // crop-прямоугольник обрезки (в пикселях изображения)
    Rect? cropRect;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Добавить баннер'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок')),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание')),
                TextField(controller: colorCtrl, decoration: const InputDecoration(labelText: 'Цвет (#RRGGBB)')),
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'ID магазина-цели')),
                TextField(controller: discountCtrl, decoration: const InputDecoration(labelText: 'Скидка (например -20%)')),
                const SizedBox(height: 12),
                TextField(
                  controller: imageUrlCtrl,
                  decoration: const InputDecoration(labelText: 'URL картинки (необязательно)'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 16),
                const Text('Предпросмотр баннера', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  width: 320,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrlCtrl.text.isNotEmpty
                        ? BannerImagePreview(
                            imageUrl: imageUrlCtrl.text,
                            cropRect: cropRect,
                            width: 320,
                            height: 160,
                          )
                        : Container(color: Colors.grey[200], child: const Icon(Icons.image)),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: imageUrlCtrl.text.isEmpty
                      ? null
                      : () async {
                          final result = await Navigator.push<Rect>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _ImageEditorDialog(
                                title: 'Редактировать изображение баннера',
                                imageUrl: imageUrlCtrl.text,
                                iconWidth: 320,
                                iconHeight: 160,
                                fullScreen: true,
                                initialCrop: cropRect,
                              ),
                            ),
                          );
                          if (result != null) {
                            cropRect = result;
                            setDialogState(() {});
                          }
                        },
                  icon: const Icon(Icons.edit),
                  label: const Text('Редактировать изображение'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                await _firestore.collection('banners').add({
                  'title': titleCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'color': colorCtrl.text.trim(),
                  'targetShopId': targetCtrl.text.trim(),
                  'discount': discountCtrl.text.trim(),
                  'imageUrl': imageUrlCtrl.text.trim(),
                  'cropRect': cropRect == null
                      ? null
                      : [cropRect!.left, cropRect!.top, cropRect!.width, cropRect!.height],
                });
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ДИАЛОГ РЕДАКТИРОВАНИЯ БАННЕРА ====================
  Future<void> _editBanner(String id, Map<String, dynamic> data) async {
    final titleCtrl = TextEditingController(text: data['title']);
    final descCtrl = TextEditingController(text: data['description']);
    final colorCtrl = TextEditingController(text: data['color']);
    final targetCtrl = TextEditingController(text: data['targetShopId']);
    final discountCtrl = TextEditingController(text: data['discount']);
    final imageUrlCtrl = TextEditingController(text: data['imageUrl'] ?? '');

    // Читаем сохранённый crop-прямоугольник
    Rect? cropRect;
    if (data['cropRect'] is List && (data['cropRect'] as List).length == 4) {
      final l = (data['cropRect'] as List).map((e) => (e as num).toDouble()).toList();
      cropRect = Rect.fromLTWH(l[0], l[1], l[2], l[3]);
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Редактировать баннер'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок')),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание')),
                TextField(controller: colorCtrl, decoration: const InputDecoration(labelText: 'Цвет (#RRGGBB)')),
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'ID магазина-цели')),
                TextField(controller: discountCtrl, decoration: const InputDecoration(labelText: 'Скидка')),
                const SizedBox(height: 12),
                TextField(
                  controller: imageUrlCtrl,
                  decoration: const InputDecoration(labelText: 'URL картинки'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 16),
                const Text('Предпросмотр баннера', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Превью выглядит ТОЧНО так же, как на главной странице
                SizedBox(
                  width: 320,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrlCtrl.text.isNotEmpty
                        ? BannerImagePreview(
                            imageUrl: imageUrlCtrl.text,
                            cropRect: cropRect,
                            width: 320,
                            height: 160,
                          )
                        : Container(color: Colors.grey[200], child: const Icon(Icons.image)),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: imageUrlCtrl.text.isEmpty
                      ? null
                      : () async {
                          final result = await Navigator.push<Rect>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _ImageEditorDialog(
                                title: 'Редактировать изображение баннера',
                                imageUrl: imageUrlCtrl.text,
                                iconWidth: 320,
                                iconHeight: 160,
                                fullScreen: true,
                                initialCrop: cropRect,
                              ),
                            ),
                          );
                          if (result != null) {
                            cropRect = result;
                            setDialogState(() {}); // обновляем превью
                          }
                        },
                  icon: const Icon(Icons.edit),
                  label: const Text('Редактировать изображение'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                await _firestore.collection('banners').doc(id).update({
                  'title': titleCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'color': colorCtrl.text.trim(),
                  'targetShopId': targetCtrl.text.trim(),
                  'discount': discountCtrl.text.trim(),
                  'imageUrl': imageUrlCtrl.text.trim(),
                  'cropRect': cropRect == null
                      ? null
                      : [cropRect!.left, cropRect!.top, cropRect!.width, cropRect!.height],
                });
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteBanner(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить баннер?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('banners').doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Управление баннерами')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('banners').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Ошибка: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final banners = snapshot.data!.docs;
          if (banners.isEmpty) return const Center(child: Text('Нет баннеров'));
          return ListView.builder(
            itemCount: banners.length,
            itemBuilder: (context, index) {
              final doc = banners[index];
              final data = doc.data() as Map<String, dynamic>;

              // Мини-превью баннера в списке
              Rect? cropRect;
              if (data['cropRect'] is List && (data['cropRect'] as List).length == 4) {
                final l = (data['cropRect'] as List).map((e) => (e as num).toDouble()).toList();
                cropRect = Rect.fromLTWH(l[0], l[1], l[2], l[3]);
              }
              final imageUrl = (data['imageUrl'] ?? '') as String;

              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: imageUrl.isNotEmpty
                      ? SizedBox(
                          width: 80,
                          height: 40,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: BannerImagePreview(
                              imageUrl: imageUrl,
                              cropRect: cropRect,
                              width: 80,
                              height: 40,
                            ),
                          ),
                        )
                      : const Icon(Icons.image, size: 40),
                  title: Text(data['title'] ?? 'Без названия'),
                  subtitle: Text(data['description'] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _editBanner(doc.id, data)),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteBanner(doc.id)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addBanner, child: const Icon(Icons.add)),
    );
  }
}

// ======================================================================
// ВИДЖЕТ ПРЕВЬЮ БАННЕРА
// Используется одинаково: в списке, в диалоге и НА ГЛАВНОЙ странице.
// Отображает картинку по crop-прямоугольнику, точно как в редакторе.
// ======================================================================
class BannerImagePreview extends StatefulWidget {
  final String imageUrl;
  final Rect? cropRect; // прямоугольник обрезки в пикселях изображения
  final double width;
  final double height;

  const BannerImagePreview({
    Key? key,
    required this.imageUrl,
    required this.cropRect,
    required this.width,
    required this.height,
  }) : super(key: key);

  @override
  State<BannerImagePreview> createState() => _BannerImagePreviewState();
}

class _BannerImagePreviewState extends State<BannerImagePreview> {
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  @override
  void didUpdateWidget(covariant BannerImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _imageSize = null;
      _loadSize();
    }
  }

  void _loadSize() {
    if (widget.imageUrl.isEmpty) return;
    Image.network(widget.imageUrl)
        .image
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener((info, _) {
      if (mounted) {
        setState(() {
          _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    // Пока картинка не загрузилась или нет crop — показываем cover
    if (widget.cropRect == null ||
        widget.cropRect!.isEmpty ||
        widget.cropRect!.width == 0 ||
        _imageSize == null) {
      return Image.network(
        widget.imageUrl,
        fit: BoxFit.cover,
        width: widget.width,
        height: widget.height,
      );
    }

    final crop = widget.cropRect!;
    // Во сколько раз растянуть изображение, чтобы crop.width занял всю ширину
    final previewScale = widget.width / crop.width;

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.translate(
          offset: Offset(-crop.left * previewScale, -crop.top * previewScale),
          child: SizedBox(
            width: _imageSize!.width * previewScale,
            height: _imageSize!.height * previewScale,
            child: Image.network(widget.imageUrl, fit: BoxFit.fill),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// ПОЛНОЭКРАННЫЙ РЕДАКТОР ИЗОБРАЖЕНИЯ
// Возвращает Rect (crop-прямоугольник в пикселях изображения) через Navigator.pop
// ======================================================================
class _ImageEditorDialog extends StatefulWidget {
  final String title;
  final String imageUrl;
  final double iconWidth;
  final double iconHeight;
  final bool fullScreen;
  final Rect? initialCrop;

  const _ImageEditorDialog({
    required this.title,
    required this.imageUrl,
    required this.iconWidth,
    required this.iconHeight,
    this.fullScreen = false,
    this.initialCrop,
  });

  @override
  State<_ImageEditorDialog> createState() => _ImageEditorDialogState();
}

class _ImageEditorDialogState extends State<_ImageEditorDialog> {
  Size? _imageSize;
  Offset _offset = Offset.zero; // левый верхний угол рамки в координатах изображения
  double _scale = 1.0; // экранных пикселей на пиксель изображения
  late double _frameAspect;
  Size _frameScreenSize = Size.zero;
  Offset _lastFocal = Offset.zero;
  double _lastScale = 1.0;
  bool _initApplied = false;

  @override
  void initState() {
    super.initState();
    _frameAspect = widget.iconWidth / widget.iconHeight;
    _loadImageSize();
  }

  void _loadImageSize() {
    if (widget.imageUrl.isEmpty) return;
    final image = Image.network(widget.imageUrl);
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (mounted) {
          setState(() {
            _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
          });
        }
      }),
    );
  }

  // Применяем начальный crop (или авто), когда известны размеры кадра и картинки
  void _applyInitialCropIfNeeded() {
    if (_initApplied) return;
    if (_imageSize == null || _frameScreenSize == Size.zero) return;
    _initApplied = true;

    if (widget.initialCrop != null && !widget.initialCrop!.isEmpty) {
      final crop = widget.initialCrop!;
      _scale = _frameScreenSize.width / crop.width;
      _offset = Offset(crop.left, crop.top);
      _clampOffset();
    } else {
      _autoFitInternal();
    }
  }

  Rect _cropRectInImage() {
    if (_imageSize == null || _frameScreenSize == Size.zero) return Rect.zero;
    final cropW = _frameSizeInImage().width;
    final cropH = _frameSizeInImage().height;
    return Rect.fromLTWH(_offset.dx, _offset.dy, cropW, cropH);
  }

  Size _frameSizeInImage() {
    if (_frameScreenSize == Size.zero) return Size.zero;
    return Size(_frameScreenSize.width / _scale, _frameScreenSize.height / _scale);
  }

  void _clampOffset() {
    if (_imageSize == null) return;
    final frameInImg = _frameSizeInImage();
    final maxX = _imageSize!.width - frameInImg.width;
    final maxY = _imageSize!.height - frameInImg.height;
    _offset = Offset(
      _offset.dx.clamp(0.0, maxX < 0 ? 0.0 : maxX),
      _offset.dy.clamp(0.0, maxY < 0 ? 0.0 : maxY),
    );
  }

  void _autoFit() {
    setState(_autoFitInternal);
  }

  // Вписывает картинку целиком в рамку (максимально, без обрезки по одной стороне)
  void _autoFitInternal() {
    if (_imageSize == null || _frameScreenSize == Size.zero) return;
    final imgAspect = _imageSize!.width / _imageSize!.height;
    Size cropInImg;
    if (imgAspect > _frameAspect) {
      final h = _imageSize!.height;
      final w = h * _frameAspect;
      cropInImg = Size(w, h);
    } else {
      final w = _imageSize!.width;
      final h = w / _frameAspect;
      cropInImg = Size(w, h);
    }
    _scale = _frameScreenSize.width / cropInImg.width;
    _offset = Offset(
      (_imageSize!.width - cropInImg.width) / 2,
      (_imageSize!.height - cropInImg.height) / 2,
    );
    _clampOffset();
  }

  @override
  Widget build(BuildContext context) {
    // fullScreen-режим (мы всегда открываем именно его)
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context), // без результата -> изменения не применятся
        ),
        actions: [
          IconButton(
            tooltip: 'Авто (вписать картинку)',
            icon: const Icon(Icons.fit_screen),
            onPressed: _imageSize == null ? null : _autoFit,
          ),
          TextButton(
            onPressed: () {
              final crop = _cropRectInImage();
              Navigator.pop(context, crop == Rect.zero ? null : crop);
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _imageSize == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // применяем стартовое положение после того как узнали размер кадра
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!_initApplied) {
                          _applyInitialCropIfNeeded();
                          if (mounted) setState(() {});
                        }
                      });
                      return _buildEditor(constraints);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildPreviewPanel(),
                ),
              ],
            ),
    );
  }

  Widget _buildEditor(BoxConstraints constraints) {
    final viewW = constraints.maxWidth;
    final viewH = constraints.maxHeight;

    // Рамка занимает большую часть области, сохраняя пропорции баннера
    double frameW, frameH;
    final maxFrameW = viewW * 0.9;
    final maxFrameH = viewH * 0.9;
    if (maxFrameW / _frameAspect <= maxFrameH) {
      frameW = maxFrameW;
      frameH = frameW / _frameAspect;
    } else {
      frameH = maxFrameH;
      frameW = frameH * _frameAspect;
    }
    _frameScreenSize = Size(frameW, frameH);

    final frameLeft = (viewW - frameW) / 2;
    final frameTop = (viewH - frameH) / 2;
    final imgLeft = frameLeft - _offset.dx * _scale;
    final imgTop = frameTop - _offset.dy * _scale;
    final imgW = _imageSize!.width * _scale;
    final imgH = _imageSize!.height * _scale;

    return GestureDetector(
      onScaleStart: (details) {
        _lastFocal = details.localFocalPoint;
        _lastScale = _scale;
      },
      onScaleUpdate: (details) {
        setState(() {
          final newScale = (_lastScale * details.scale).clamp(0.05, 10.0);
          final delta = details.localFocalPoint - _lastFocal;
          _lastFocal = details.localFocalPoint;
          _offset = Offset(_offset.dx - delta.dx / _scale, _offset.dy - delta.dy / _scale);
          _scale = newScale;
          _clampOffset();
        });
      },
      child: ClipRect(
        child: Container(
          width: viewW,
          height: viewH,
          color: Colors.grey[300],
          child: Stack(
            children: [
              Positioned(
                left: imgLeft,
                top: imgTop,
                width: imgW,
                height: imgH,
                child: Image.network(widget.imageUrl, fit: BoxFit.fill),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _OverlayPainter(frameRect: Rect.fromLTWH(frameLeft, frameTop, frameW, frameH)),
                ),
              ),
              Positioned(
                left: frameLeft,
                top: frameTop,
                width: frameW,
                height: frameH,
                child: CustomPaint(painter: _DashedBorderPainter()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    const double previewW = 200;
    final previewH = previewW / _frameAspect;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Предпросмотр', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: previewW,
              height: previewH,
              child: _buildCropPreview(previewW, previewH),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCropPreview(double pw, double ph) {
    final crop = _cropRectInImage();
    if (crop.isEmpty || crop.width == 0) return const SizedBox();
    final previewScale = pw / crop.width;
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.translate(
          offset: Offset(-crop.left * previewScale, -crop.top * previewScale),
          child: SizedBox(
            width: _imageSize!.width * previewScale,
            height: _imageSize!.height * previewScale,
            child: Image.network(widget.imageUrl, fit: BoxFit.fill),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dashWidth = 6.0, dashSpace = 4.0;
    for (double x = 0; x < size.width; x += dashWidth + dashSpace) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      canvas.drawLine(Offset(x, size.height), Offset(x + dashWidth, size.height), paint);
    }
    for (double y = 0; y < size.height; y += dashWidth + dashSpace) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dashWidth), paint);
      canvas.drawLine(Offset(size.width, y), Offset(size.width, y + dashWidth), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OverlayPainter extends CustomPainter {
  final Rect frameRect;
  _OverlayPainter({required this.frameRect});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.5);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(frameRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => oldDelegate.frameRect != frameRect;
}