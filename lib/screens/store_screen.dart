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
  int _todayActivations = 0;
  int _newClientsWeek = 0;
  Map<String, dynamic>? _nearestPromotion;
  Map<String, dynamic>? _lastNotification;

  @override
  void initState() {
    super.initState();
    _getStoreId();
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

  Future<void> _updateShop(Map<String, dynamic> data) async {
    await _firestore.collection('shops').doc(_storeId).update(data);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
    _shopData.addAll(data);
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

  // ИСПРАВЛЕННЫЙ МЕТОД ПОВЫШЕНИЯ ПРИОРИТЕТА (работает)
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
    final imageUrl = _shopData['imageUrl'] ?? '';

    return SingleChildScrollView(
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
                  const Text('Название магазина', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: _shopData['name'] ?? '',
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    onChanged: (value) => _updateShop({'name': value}),
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
                  const Text('Ссылка на логотип (URL)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: imageUrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'https://...'),
                    onChanged: (value) => _updateShop({'imageUrl': value}),
                  ),
                  if (imageUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Image.network(imageUrl, height: 80, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
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
                  const Text('Приоритет', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Chip(label: Text('$priority'), backgroundColor: Colors.blue.shade100),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Чем выше приоритет, тем чаще ваши акции предлагаются пользователям. Повысьте приоритет, чтобы увеличить поток клиентов.',
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
                    Text('Нет активных акций. Создайте акцию в календаре.', style: TextStyle(color: Colors.grey[600]))
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_nearestPromotion!['title'], style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('${_nearestPromotion!['discount']} — действительна с ${DateFormat('dd.MM.yyyy').format(_nearestPromotion!['startDate'])} по ${DateFormat('dd.MM.yyyy').format(_nearestPromotion!['endDate'])}', style: const TextStyle(fontSize: 12)),
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
                    Text('У вас пока нет уведомлений. Создайте уведомление в разделе статистики.', style: TextStyle(color: Colors.grey[600]))
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_lastNotification!['title'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(_lastNotification!['body'], style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(DateFormat('dd.MM.yyyy HH:mm').format(_lastNotification!['timestamp']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
                    '2. Каждая активация вашей акции приносит вам клиента (первые продажи) или повторную продажу.\n'
                    '3. Вы можете планировать акции в календаре, управлять баннерами и отправлять уведомления.\n'
                    '4. Чем выше приоритет, тем чаще ваша акция предлагается пользователю в игровом выборе.',
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