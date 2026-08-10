import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'promotions_screen.dart';
import 'stats_screen.dart';
import 'package:admin_panel/utils/audit.dart';   // 🆕 сервис аудита

// ----------------------------------------------------------------------
// ОСНОВНОЙ ЭКРАН МАГАЗИНА (StoreScreen)
// ----------------------------------------------------------------------
class StoreScreen extends StatefulWidget {
  final Function(int) onTabSelected;
  const StoreScreen({Key? key, required this.onTabSelected}) : super(key: key);

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  String? _storeId;
  bool _loading = true;
  Map<String, dynamic> _shopData = {};

  // Текстовые контроллеры
  final _nameController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _shortDiscountController = TextEditingController();
  final _discountController = TextEditingController();
  final _infoImageUrlController = TextEditingController();

  // Координаты на карте
  final _mapXController = TextEditingController();
  final _mapYController = TextEditingController();
  final _mapWidthController = TextEditingController();
  final _mapHeightController = TextEditingController();

  // Контроллеры трансформаций (матрицы 4x4)
  final TransformationController _logoTransformController = TransformationController();
  final TransformationController _infoImageTransformController = TransformationController();

  // Статистика
  int _todayActivations = 0;
  int _newClientsWeek = 0;
  Map<String, dynamic>? _nearestPromotion;
  Map<String, dynamic>? _lastNotification;

  @override
  void initState() {
    super.initState();
    _getStoreId();
    _imageUrlController.addListener(_onImageUrlChanged);
    _infoImageUrlController.addListener(_onInfoImageUrlChanged);
  }

  @override
  void dispose() {
    _imageUrlController.removeListener(_onImageUrlChanged);
    _infoImageUrlController.removeListener(_onInfoImageUrlChanged);
    _nameController.dispose();
    _imageUrlController.dispose();
    _descriptionController.dispose();
    _shortDiscountController.dispose();
    _discountController.dispose();
    _infoImageUrlController.dispose();
    _mapXController.dispose();
    _mapYController.dispose();
    _mapWidthController.dispose();
    _mapHeightController.dispose();
    _logoTransformController.dispose();
    _infoImageTransformController.dispose();
    super.dispose();
  }

  void _onImageUrlChanged() {
    _logoTransformController.value = Matrix4.identity();
    if (mounted) setState(() {});
  }

  void _onInfoImageUrlChanged() {
    _infoImageTransformController.value = Matrix4.identity();
    if (mounted) setState(() {});
  }

  Future<void> _getStoreId() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      final doc = await _firestore.collection('users').doc(user.email!).get();
      if (mounted) {
        setState(() {
          _storeId = doc.data()?['storeId'] as String?;
        });
      }
      if (_storeId != null) {
        await _loadShopData();
        await _loadStats();
        await _loadNearestPromotion();
        await _loadLastNotification();
      }
      if (mounted) setState(() => _loading = false);
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadShopData() async {
    final doc = await _firestore.collection('shops').doc(_storeId).get();
    if (doc.exists) {
      _shopData = doc.data() as Map<String, dynamic>;
      _nameController.text = _shopData['name'] ?? '';
      _imageUrlController.text = _shopData['imageUrl'] ?? '';
      _descriptionController.text = _shopData['description'] ?? '';
      _shortDiscountController.text = _shopData['shortDiscount'] ?? '';
      _discountController.text = _shopData['discount'] ?? '';
      _infoImageUrlController.text = _shopData['infoImageUrl'] ?? '';
      _mapXController.text = (_shopData['mapX'] ?? 0.5).toString();
      _mapYController.text = (_shopData['mapY'] ?? 0.5).toString();
      _mapWidthController.text = (_shopData['mapWidth'] ?? 0.1).toString();
      _mapHeightController.text = (_shopData['mapHeight'] ?? 0.1).toString();

      _restoreTransform(_logoTransformController, _shopData['imageTransform']);
      _restoreTransform(_infoImageTransformController, _shopData['infoImageTransform']);
    }
    if (mounted) setState(() {});
  }

  void _restoreTransform(TransformationController controller, dynamic raw) {
    if (raw is List && raw.length == 16) {
      final matrix = Matrix4.fromList(raw.cast<double>());
      controller.value = matrix;
    } else {
      controller.value = Matrix4.identity();
    }
  }

  Future<void> _loadStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = now.subtract(const Duration(days: 7));

    final todayQuery = await _firestore
        .collection('sales')
        .where('shopId', isEqualTo: _storeId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .get();
    _todayActivations = todayQuery.docs.length;

    final weekQuery = await _firestore
        .collection('sales')
        .where('shopId', isEqualTo: _storeId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .where('step', isEqualTo: 1)
        .get();
    _newClientsWeek = weekQuery.docs.length;
  }

  Future<void> _loadNearestPromotion() async {
    final now = DateTime.now();
    final snapshot = await _firestore
        .collection('store_promotions')
        .where('shopId', isEqualTo: _storeId)
        .where('endDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('startDate')
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) {
      final data = snapshot.docs.first.data();
      _nearestPromotion = {
        'id': snapshot.docs.first.id,
        'title': data['title'],
        'startDate': (data['startDate'] as Timestamp).toDate(),
        'endDate': (data['endDate'] as Timestamp).toDate(),
        'discount': data['discount'],
      };
    } else {
      _nearestPromotion = null;
    }
  }

  Future<void> _loadLastNotification() async {
    final snapshot = await _firestore
        .collection('notifications')
        .where('shopId', isEqualTo: _storeId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) {
      final data = snapshot.docs.first.data();
      _lastNotification = {
        'title': data['title'],
        'body': data['body'],
        'timestamp': (data['timestamp'] as Timestamp).toDate(),
      };
    } else {
      _lastNotification = null;
    }
  }

  Future<void> _saveAllChanges() async {
    final updatedData = {
      'name': _nameController.text.trim(),
      'imageUrl': _imageUrlController.text.trim(),
      'description': _descriptionController.text.trim(),
      'shortDiscount': _shortDiscountController.text.trim(),
      'discount': _discountController.text.trim(),
      'infoImageUrl': _infoImageUrlController.text.trim(),
      'mapX': double.tryParse(_mapXController.text) ?? 0.5,
      'mapY': double.tryParse(_mapYController.text) ?? 0.5,
      'mapWidth': double.tryParse(_mapWidthController.text) ?? 0.1,
      'mapHeight': double.tryParse(_mapHeightController.text) ?? 0.1,
      'imageTransform': _logoTransformController.value.storage.toList(),
      'infoImageTransform': _infoImageTransformController.value.storage.toList(),
    };

    await _firestore.collection('shops').doc(_storeId).update(updatedData);

    // 🆕 Аудит изменения магазина
    AuditLogger.log(
      action: 'update',
      collection: 'shops',
      docId: _storeId!,
      changes: updatedData,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Все изменения сохранены')));
    }
    _shopData.addAll(updatedData);
    setState(() {});
  }

  // ==================== НОВЫЙ РЕДАКТОР ИЗОБРАЖЕНИЯ (МАТЕМАТИЧЕСКИ ТОЧНЫЙ) ====================
  Future<void> _openImageEditor({
    required String title,
    required TransformationController controller,
    required String imageUrl,
  }) async {
    final Rect? cropRect = await showDialog<Rect>(
      context: context,
      builder: (ctx) => _ImageEditorDialog(
        title: title,
        imageUrl: imageUrl,
        iconWidth: 130,
        iconHeight: 100,
      ),
    );

    if (cropRect != null && mounted) {
      final scaleX = 130.0 / cropRect.width;
      final scaleY = 100.0 / cropRect.height;
      final scale = math.min(scaleX, scaleY);
      final tx = -cropRect.left * scale;
      final ty = -cropRect.top * scale;
      final matrix = Matrix4.identity()
        ..scale(scale)
        ..translate(tx / scale, ty / scale);
      controller.value = matrix;
      setState(() {});
    }
  }

  void _goToCalendar() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PromotionsScreen()));
  }

  void _goToStats() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()));
  }

  void _goToNotifications() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen(initialTabIndex: 2)));
  }

  Future<void> _onUpgradePriority() async {
    final currentPriority = _shopData['priority'] ?? 1;
    if (currentPriority >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Максимальный приоритет уже достигнут')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Повысить приоритет'),
        content: Text('Ваш текущий приоритет: $currentPriority\nПовысить до ${currentPriority + 1} за 5000 руб.?\n(В боевой версии здесь будет платёжный шлюз)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Оплатить')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('shops').doc(_storeId).update({'priority': currentPriority + 1});

      // 🆕 Аудит повышения приоритета
      AuditLogger.log(
        action: 'update',
        collection: 'shops',
        docId: _storeId!,
        changes: {'priority': currentPriority + 1},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Приоритет повышен!')));
        setState(() => _shopData['priority'] = currentPriority + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_storeId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Не удалось определить ваш магазин. Обратитесь к администратору.'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Выйти')),
          ],
        ),
      );
    }

    final priority = _shopData['priority'] ?? 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Логотип для главного экрана
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🖼️ Логотип для главного экрана', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Это изображение будет показываться в карточках магазина на главном экране приложения.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _imageUrlController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'https://...',
                      hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        height: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _imageUrlController.text.isNotEmpty
                              ? Transform(
                                  transform: _logoTransformController.value,
                                  child: Image.network(_imageUrlController.text, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image))))
                              : Container(color: Colors.grey[200], child: const Icon(Icons.image)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => _openImageEditor(
                          title: 'Редактировать логотип',
                          controller: _logoTransformController,
                          imageUrl: _imageUrlController.text,
                        ),
                        icon: const Icon(Icons.edit),
                        label: const Text('Редактировать'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Информация о магазине для пользователей (поля с бледными подсказками)
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('📋 Информация о магазине для пользователей',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Эти данные увидят покупатели, когда нажмут на значок информации (i) в приложении.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  const Text('Название магазина', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Например: "Кофейня Арома"',
                      hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Описание магазина', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Расскажите о вашем магазине, особенностях, атмосфере',
                      hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Краткая скидка (на карточке)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _shortDiscountController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '-30% на джинсы',
                      hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Подробное описание акции', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _discountController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Например: "Скидка 30% на джинсы из прошлой коллекции до 31 июля"',
                      hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('🖼️ Фото для подробной информации', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Это изображение будет показано в полном информационном окне.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _infoImageUrlController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'https://... (ссылка на красивое фото магазина)',
                      hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        height: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _infoImageUrlController.text.isNotEmpty
                              ? Transform(
                                  transform: _infoImageTransformController.value,
                                  child: Image.network(_infoImageUrlController.text, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image))))
                              : Container(color: Colors.grey[200], child: const Icon(Icons.image)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => _openImageEditor(
                          title: 'Редактировать фото для информации',
                          controller: _infoImageTransformController,
                          imageUrl: _infoImageUrlController.text,
                        ),
                        icon: const Icon(Icons.edit),
                        label: const Text('Редактировать'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Координаты на карте
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📍 Позиция на карте ТЦ', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _mapXController,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: 'X (0.0 - 1.0)',
                            hintText: '0.5',
                            hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _mapYController,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: 'Y (0.0 - 1.0)',
                            hintText: '0.5',
                            hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _mapWidthController,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: 'Ширина на карте (0..1)',
                            hintText: '0.1',
                            hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _mapHeightController,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: 'Высота на карте (0..1)',
                            hintText: '0.1',
                            hintStyle: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic),
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Кнопка сохранения
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _saveAllChanges,
                icon: const Icon(Icons.save),
                label: const Text('Сохранить изменения'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ),

          // Приоритет, ближайшая акция, статистика, уведомления, как это работает – без изменений
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Приоритет', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Chip(label: Text('$priority'), backgroundColor: Colors.blue.shade100),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Чем выше приоритет, тем чаще ваши акции предлагаются пользователям.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _onUpgradePriority,
                    icon: const Icon(Icons.trending_up),
                    label: const Text('Повысить приоритет'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  ),
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
                  const Text('Ближайшая акция', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_nearestPromotion == null)
                    Text('Нет активных акций.', style: TextStyle(color: Colors.grey[600]))
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_nearestPromotion!['title'], style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('${_nearestPromotion!['discount']} — с ${DateFormat('dd.MM.yyyy').format(_nearestPromotion!['startDate'])} по ${DateFormat('dd.MM.yyyy').format(_nearestPromotion!['endDate'])}',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _goToCalendar,
                    child: const Text('Все акции'),
                  ),
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
                  const Text('Статистика', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          Text('$_todayActivations', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const Text('активаций сегодня', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          Text('$_newClientsWeek', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const Text('новых клиентов за неделю', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _goToStats,
                    child: const Text('Подробнее'),
                  ),
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
                  const Text('Последнее уведомление', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_lastNotification == null)
                    Text('Нет уведомлений.', style: TextStyle(color: Colors.grey[600]))
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_lastNotification!['title'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(_lastNotification!['body'], style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(DateFormat('dd.MM.yyyy HH:mm').format(_lastNotification!['timestamp']),
                            style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _goToNotifications,
                    child: const Text('Все уведомления'),
                  ),
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
                  const Text('Как это работает?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Пользователь проходит путь из 5 магазинов, сканируя QR-коды.\n'
                    '2. Каждая активация вашей акции приносит вам клиента.\n'
                    '3. Вы можете планировать акции, управлять баннерами и отправлять уведомления.\n'
                    '4. Чем выше приоритет, тем чаще ваша акция предлагается.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// ВСПОМОГАТЕЛЬНЫЕ КЛАССЫ ДЛЯ РЕДАКТОРА
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
        if (mounted) {
          setState(() {
            _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
          });
        }
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
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => _buildEditor(constraints),
                    ),
                  ),
                  const SizedBox(width: 24),
                  _buildPreviewPanel(),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _cropRectInImage()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _buildEditor(BoxConstraints constraints) {
    final viewW = constraints.maxWidth;
    final viewH = constraints.maxHeight;

    double frameW, frameH;
    final base = math.min(viewW, viewH) * 0.5;
    if (_frameAspect >= 1) {
      frameW = base;
      frameH = base / _frameAspect;
    } else {
      frameH = base;
      frameW = base * _frameAspect;
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

          _offset = Offset(
            _offset.dx - delta.dx / _scale,
            _offset.dy - delta.dy / _scale,
          );
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
    const double previewSize = 130;
    double pw, ph;
    if (_frameAspect >= 1) {
      pw = previewSize;
      ph = previewSize / _frameAspect;
    } else {
      ph = previewSize;
      pw = previewSize * _frameAspect;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
            child: SizedBox(width: pw, height: ph, child: _buildCropPreview(pw, ph)),
          ),
        ),
        const SizedBox(height: 8),
        Text('${widget.iconWidth.toInt()}x${widget.iconHeight.toInt()}',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _autoFit,
          icon: const Icon(Icons.fit_screen, size: 16),
          label: const Text('Авто'),
        ),
      ],
    );
  }

  Widget _buildCropPreview(double pw, double ph) {
    final crop = _cropRectInImage();
    if (crop.isEmpty) return const SizedBox();
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

  void _autoFit() {
    setState(() {
      if (_imageSize == null) return;
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
    });
  }
}

// Рисовальщик пунктирной рамки
class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 4.0;

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

// Затемнение вне рамки
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