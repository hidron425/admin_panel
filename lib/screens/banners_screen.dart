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

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              TextField(controller: imageUrlCtrl, decoration: const InputDecoration(labelText: 'URL картинки (необязательно)')),
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
                'imageTransform': [], // пустая матрица
              });
              Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
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

    // Локальный контроллер для редактирования изображения
    final TransformationController transformCtrl = TransformationController();
    // Восстанавливаем матрицу, если есть
    if (data['imageTransform'] is List && (data['imageTransform'] as List).length == 16) {
      final list = (data['imageTransform'] as List).cast<double>();
      transformCtrl.value = Matrix4.fromList(list);
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
                TextField(controller: imageUrlCtrl, decoration: const InputDecoration(labelText: 'URL картинки')),
                const SizedBox(height: 12),
                // Превью и кнопка редактора
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      height: 100,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: imageUrlCtrl.text.isNotEmpty
                            ? Transform(
                                transform: transformCtrl.value,
                                child: Image.network(imageUrlCtrl.text, fit: BoxFit.cover),
                              )
                            : Container(color: Colors.grey[200], child: const Icon(Icons.image)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final Rect? cropRect = await showDialog<Rect>(
                          context: context,
                          builder: (_) => _ImageEditorDialog(
                            title: 'Редактировать изображение баннера',
                            imageUrl: imageUrlCtrl.text,
                            iconWidth: 130,   // размер превью
                            iconHeight: 100,
                          ),
                        );
                        if (cropRect != null) {
                          final scaleX = 130.0 / cropRect.width;
                          final scaleY = 100.0 / cropRect.height;
                          final scale = math.min(scaleX, scaleY);
                          final tx = -cropRect.left * scale;
                          final ty = -cropRect.top * scale;
                          final matrix = Matrix4.identity()
                            ..scale(scale)
                            ..translate(tx / scale, ty / scale);
                          transformCtrl.value = matrix;
                          setDialogState(() {}); // обновить превью
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Редактировать'),
                    ),
                  ],
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
                  'imageTransform': transformCtrl.value.storage.toList(),
                });
                Navigator.pop(context);
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
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final banners = snapshot.data!.docs;
          if (banners.isEmpty) return const Center(child: Text('Нет баннеров'));
          return ListView.builder(
            itemCount: banners.length,
            itemBuilder: (context, index) {
              final doc = banners[index];
              final data = doc.data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
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
// ВСПОМОГАТЕЛЬНЫЕ КЛАССЫ ДЛЯ РЕДАКТОРА (скопированы из StoreScreen)
// ======================================================================

class _ImageEditorDialog extends StatefulWidget {
  final String title;
  final String imageUrl;
  final double iconWidth;
  final double iconHeight;

  const _ImageEditorDialog({
    required this.title,
    required this.imageUrl,
    required this.iconWidth,
    required this.iconHeight,
  });

  @override
  State<_ImageEditorDialog> createState() => _ImageEditorDialogState();
}

class _ImageEditorDialogState extends State<_ImageEditorDialog> {
  Size? _imageSize;
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  late double _frameAspect = widget.iconWidth / widget.iconHeight;
  Size _frameScreenSize = Size.zero;
  Offset _lastFocal = Offset.zero;
  double _lastScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  void _loadImageSize() {
    final image = Image.network(widget.imageUrl);
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (mounted) setState(() {
          _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
        });
      }),
    );
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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final editorWidth = screenSize.width * 0.6;
    final editorHeight = screenSize.height * 0.6;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: editorWidth,
        height: editorHeight,
        child: _imageSize == null
            ? const Center(child: CircularProgressIndicator())
            : Row(
                children: [
                  Expanded(child: LayoutBuilder(builder: (context, constraints) => _buildEditor(constraints))),
                  const SizedBox(width: 24),
                  _buildPreviewPanel(),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(onPressed: () => Navigator.pop(context, _cropRectInImage()), child: const Text('Сохранить')),
      ],
    );
  }

  Widget _buildEditor(BoxConstraints constraints) {
    final viewW = constraints.maxWidth;
    final viewH = constraints.maxHeight;
    double frameW, frameH;
    final base = math.min(viewW, viewH) * 0.5;
    if (_frameAspect >= 1) {
      frameW = base; frameH = base / _frameAspect;
    } else {
      frameH = base; frameW = base * _frameAspect;
    }
    _frameScreenSize = Size(frameW, frameH);
    final frameLeft = (viewW - frameW) / 2;
    final frameTop = (viewH - frameH) / 2;
    final imgLeft = frameLeft - _offset.dx * _scale;
    final imgTop = frameTop - _offset.dy * _scale;
    final imgW = _imageSize!.width * _scale;
    final imgH = _imageSize!.height * _scale;

    return GestureDetector(
      onScaleStart: (details) { _lastFocal = details.localFocalPoint; _lastScale = _scale; },
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
          width: viewW, height: viewH, color: Colors.grey[300],
          child: Stack(
            children: [
              Positioned(left: imgLeft, top: imgTop, width: imgW, height: imgH, child: Image.network(widget.imageUrl, fit: BoxFit.fill)),
              Positioned.fill(child: CustomPaint(painter: _OverlayPainter(frameRect: Rect.fromLTWH(frameLeft, frameTop, frameW, frameH)))),
              Positioned(left: frameLeft, top: frameTop, width: frameW, height: frameH, child: CustomPaint(painter: _DashedBorderPainter())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    const double previewSize = 130;
    double pw, ph;
    if (_frameAspect >= 1) { pw = previewSize; ph = previewSize / _frameAspect; }
    else { ph = previewSize; pw = previewSize * _frameAspect; }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Предпросмотр', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12)),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: pw, height: ph, child: _buildCropPreview(pw, ph))),
        ),
        const SizedBox(height: 8),
        Text('${widget.iconWidth.toInt()}x${widget.iconHeight.toInt()}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: _autoFit, icon: const Icon(Icons.fit_screen, size: 16), label: const Text('Авто')),
      ],
    );
  }

  Widget _buildCropPreview(double pw, double ph) {
    final crop = _cropRectInImage();
    if (crop.isEmpty) return const SizedBox();
    final previewScale = pw / crop.width;
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft, minWidth: 0, minHeight: 0, maxWidth: double.infinity, maxHeight: double.infinity,
        child: Transform.translate(
          offset: Offset(-crop.left * previewScale, -crop.top * previewScale),
          child: SizedBox(width: _imageSize!.width * previewScale, height: _imageSize!.height * previewScale, child: Image.network(widget.imageUrl, fit: BoxFit.fill)),
        ),
      ),
    );
  }

  void _autoFit() {
    setState(() {
      if (_imageSize == null) return;
      final imgAspect = _imageSize!.width / _imageSize!.height;
      Size cropInImg;
      if (imgAspect > _frameAspect) { final h = _imageSize!.height; final w = h * _frameAspect; cropInImg = Size(w, h); }
      else { final w = _imageSize!.width; final h = w / _frameAspect; cropInImg = Size(w, h); }
      _scale = _frameScreenSize.width / cropInImg.width;
      _offset = Offset((_imageSize!.width - cropInImg.width) / 2, (_imageSize!.height - cropInImg.height) / 2);
      _clampOffset();
    });
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke;
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
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height))..addRect(frameRect)..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => oldDelegate.frameRect != frameRect;
}