import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'promotions_screen.dart';
import 'stats_screen.dart';

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

  // Контроллеры для редактируемых полей
  final _nameController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _shortDiscountController = TextEditingController();
  final _discountController = TextEditingController();
  final _infoImageUrlController = TextEditingController();
  final _mapXController = TextEditingController();
  final _mapYController = TextEditingController();
  final _mapWidthController = TextEditingController();   // 🆕
  final _mapHeightController = TextEditingController();  // 🆕

  int _todayActivations = 0;
  int _newClientsWeek = 0;
  Map<String, dynamic>? _nearestPromotion;
  Map<String, dynamic>? _lastNotification;

  @override
  void initState() {
    super.initState();
    _getStoreId();
  }

  @override
  void dispose() {
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
    super.dispose();
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
      // Заполняем контроллеры актуальными данными
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
      if (mounted) setState(() {});
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

  // Единая кнопка сохранения
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
    };

    await _firestore.collection('shops').doc(_storeId).update(updatedData);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Все изменения сохранены')));
    // Обновляем локальные данные, чтобы UI отобразил новые значения (например, фото)
    _shopData.addAll(updatedData);
    setState(() {});
  }

  void _goToCalendar() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PromotionsScreen()),
    );
  }

  void _goToStats() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StatsScreen()),
    );
  }

  void _goToNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StatsScreen(initialTabIndex: 2)),
    );
  }

  Future<void> _onUpgradePriority() async {
    final currentPriority = _shopData['priority'] ?? 1;
    if (currentPriority >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Максимальный приоритет уже достигнут')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Повысить приоритет'),
        content: Text('Ваш текущий приоритет: $currentPriority\n'
            'Повысить до ${currentPriority + 1} за 5000 руб.?\n'
            '(В боевой версии здесь будет платёжный шлюз)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Оплатить')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('shops').doc(_storeId).update({
        'priority': currentPriority + 1,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Приоритет повышен!')));
        setState(() => _shopData['priority'] = currentPriority + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_storeId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Не удалось определить ваш магазин. Обратитесь к администратору.'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('Выйти'),
            ),
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
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'https://...'),
                  ),
                  if (_imageUrlController.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Image.network(_imageUrlController.text, height: 80,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                    ),
                ],
              ),
            ),
          ),
          // Блок "Информация о магазине для пользователей"
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
                  // Название
                  const Text('Название магазина', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Например: "Кофейня Арома"',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Описание
                  const Text('Описание магазина', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Расскажите о вашем магазине, особенностях, атмосфере',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  // Краткая скидка (для карточек)
                  const Text('Краткая скидка (на карточке)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Показывается в карточке магазина на главном экране. Должна быть короткой, например: "-30% на джинсы".',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _shortDiscountController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '-30% на джинсы',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Подробное описание акции
                  const Text('Подробное описание акции', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Полный текст акции, который увидит пользователь в информационном окне.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _discountController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Например: "Скидка 30% на джинсы из прошлой коллекции до 31 июля"',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  // Фото для подробной информации
                  const Text('🖼️ Фото для подробной информации', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Это изображение будет показано в полном информационном окне (большое, привлекательное).',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _infoImageUrlController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'https://... (ссылка на красивое фото магазина)',
                    ),
                  ),
                  if (_infoImageUrlController.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Image.network(_infoImageUrlController.text, height: 120, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                    ),
                  const SizedBox(height: 16),
                  // Координаты и размеры для карты
                  const Text('📍 Расположение на карте ТЦ', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Координаты центра магазина (0.0 - 1.0)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _mapXController,
                          decoration: const InputDecoration(labelText: 'X', border: OutlineInputBorder()),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _mapYController,
                          decoration: const InputDecoration(labelText: 'Y', border: OutlineInputBorder()),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _mapWidthController,
                          decoration: const InputDecoration(labelText: 'Ширина (0..1)', border: OutlineInputBorder()),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _mapHeightController,
                          decoration: const InputDecoration(labelText: 'Высота (0..1)', border: OutlineInputBorder()),
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
          // Приоритет
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
          // Ближайшая акция (календарь)
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
          // Статистика
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
          // Последнее уведомление
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
          // Как это работает
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