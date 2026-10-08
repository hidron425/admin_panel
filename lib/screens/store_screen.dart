import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'promotions_screen.dart';
import 'stats_screen.dart';
import 'push_notification_screen.dart';
import 'package:admin_panel/utils/audit.dart';

class StoreScreen extends StatefulWidget {
  final Function(int) onTabSelected;
  const StoreScreen({Key? key, required this.onTabSelected}) : super(key: key);

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  String? _storeId;
  bool _loading = true;
  Map<String, dynamic> _shopData = {};

  final _nameController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _shortDiscountController = TextEditingController();
  final _discountController = TextEditingController();
  final _infoImageUrlController = TextEditingController();

  final _mapXController = TextEditingController();
  final _mapYController = TextEditingController();
  final _mapWidthController = TextEditingController();
  final _mapHeightController = TextEditingController();

  final TransformationController _logoTransformController = TransformationController();
  final TransformationController _infoImageTransformController = TransformationController();

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
    try {
      final email = _sb.auth.currentUser?.email;
      if (email != null) {
        final data = await _sb
            .from('user_metadata')
            .select('store_id')
            .eq('email', email)
            .maybeSingle();
        if (mounted) {
          setState(() => _storeId = data?['store_id'] as String?);
        }
        if (_storeId != null) {
          await _loadShopData();
          await _loadStats();
          await _loadNearestPromotion();
          await _loadLastNotification();
          await _loadActivity();          // ← добавить
          await _loadAnnouncements();
        }
      }
    } catch (e) {
      debugPrint('❌ _getStoreId: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadShopData() async {
    try {
      final data = await _sb
          .from('shops')
          .select()
          .eq('firestore_id', _storeId!)
          .maybeSingle();
      if (data != null) {
        _shopData = Map<String, dynamic>.from(data);
        _nameController.text = _shopData['name'] ?? '';
        _imageUrlController.text = _shopData['image_url'] ?? '';
        _descriptionController.text = _shopData['description'] ?? '';
        _shortDiscountController.text = _shopData['short_discount'] ?? '';
        _discountController.text = _shopData['discount'] ?? '';
        _infoImageUrlController.text = _shopData['info_image_url'] ?? '';
        _mapXController.text = (_shopData['map_x'] ?? 0.5).toString();
        _mapYController.text = (_shopData['map_y'] ?? 0.5).toString();
        _mapWidthController.text = (_shopData['map_width'] ?? 0.1).toString();
        _mapHeightController.text = (_shopData['map_height'] ?? 0.1).toString();

        _restoreTransform(_logoTransformController, _shopData['image_transform']);
        _restoreTransform(_infoImageTransformController, _shopData['info_image_transform']);
      }
    } catch (e) {
      debugPrint('❌ _loadShopData: $e');
    }
    if (mounted) setState(() {});
  }

  void _restoreTransform(TransformationController controller, dynamic raw) {
    if (raw is List && raw.length == 16) {
      try {
        controller.value = Matrix4.fromList(raw.map((e) => (e as num).toDouble()).toList());
      } catch (_) {
        controller.value = Matrix4.identity();
      }
    } else {
      controller.value = Matrix4.identity();
    }
  }

  Future<void> _loadStats() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = now.subtract(const Duration(days: 7));

      final todayData = await _sb
          .from('sales')
          .select('firestore_id')
          .eq('shop_id', _storeId!)
          .gte('created_at', todayStart.toIso8601String());
      _todayActivations = (todayData as List).length;

      final weekData = await _sb
          .from('sales')
          .select('firestore_id')
          .eq('shop_id', _storeId!)
          .eq('step', 1)
          .gte('created_at', weekStart.toIso8601String());
      _newClientsWeek = (weekData as List).length;
    } catch (e) {
      debugPrint('❌ _loadStats: $e');
    }
  }

  Future<void> _loadNearestPromotion() async {
    try {
      final now = DateTime.now();
      final data = await _sb
          .from('store_promotions')
          .select()
          .eq('shop_id', _storeId!)
          .gte('end_date', now.toIso8601String())
          .order('start_date', ascending: true)
          .limit(1)
          .maybeSingle();

      if (data != null) {
        _nearestPromotion = {
          'id': data['firestore_id'] ?? data['id'],
          'title': data['title'],
          'startDate': DateTime.tryParse(data['start_date']?.toString() ?? '') ?? now,
          'endDate': DateTime.tryParse(data['end_date']?.toString() ?? '') ?? now,
          'discount': data['discount'],
        };
      } else {
        _nearestPromotion = null;
      }
    } catch (e) {
      debugPrint('❌ _loadNearestPromotion: $e');
      _nearestPromotion = null;
    }
  }

  Future<void> _loadLastNotification() async {
    try {
      final data = await _sb
          .from('push_queue')
          .select()
          .eq('shop_id', _storeId!)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data != null) {
        _lastNotification = {
          'title': data['title'],
          'body': data['body'],
          'timestamp': DateTime.tryParse(data['created_at']?.toString() ?? '') ?? DateTime.now(),
        };
      } else {
        _lastNotification = null;
      }
    } catch (e) {
      debugPrint('❌ _loadLastNotification: $e');
      _lastNotification = null;
    }
  }

  Future<void> _saveAllChanges() async {
    final updatedData = <String, dynamic>{
      'name': _nameController.text.trim(),
      'image_url': _imageUrlController.text.trim(),
      'description': _descriptionController.text.trim(),
      'short_discount': _shortDiscountController.text.trim(),
      'discount': _discountController.text.trim(),
      'info_image_url': _infoImageUrlController.text.trim(),
      'map_x': double.tryParse(_mapXController.text) ?? 0.5,
      'map_y': double.tryParse(_mapYController.text) ?? 0.5,
      'map_width': double.tryParse(_mapWidthController.text) ?? 0.1,
      'map_height': double.tryParse(_mapHeightController.text) ?? 0.1,
      'image_transform': _logoTransformController.value.storage.toList(),
      'info_image_transform': _infoImageTransformController.value.storage.toList(),
    };

    try {
      await _sb.from('shops').update(updatedData).eq('firestore_id', _storeId!);
      AuditLogger.log(
        action: 'update',
        collection: 'shops',
        docId: _storeId!,
        changes: updatedData,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Все изменения сохранены')),
        );
      }
      _shopData.addAll(updatedData);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ _saveAllChanges: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

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
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PushNotificationScreen()));
  }

  Future<void> _onUpgradePriority() async {
    final currentPriority = (_shopData['priority'] as num?)?.toInt() ?? 1;
    if (currentPriority >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Максимальный приоритет уже достигнут')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Повысить приоритет'),
        content: Text(
            'Ваш текущий приоритет: $currentPriority\nПовысить до ${currentPriority + 1} за 5000 руб.?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Оплатить')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _sb
            .from('shops')
            .update({'priority': currentPriority + 1}).eq('firestore_id', _storeId!);
        AuditLogger.log(
          action: 'update',
          collection: 'shops',
          docId: _storeId!,
          changes: {'priority': currentPriority + 1},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Приоритет повышен!')),
          );
          setState(() => _shopData['priority'] = currentPriority + 1);
        }
      } catch (e) {
        debugPrint('❌ _onUpgradePriority: $e');
      }
    }
  }

  // ---------- Данные для CRM-блоков ----------
  List<Map<String, dynamic>> _activity = [];
  List<Map<String, dynamic>> _announcements = [];
  int _subscribersCount = 0;

  Future<void> _loadActivity() async {
    try {
      final events = <Map<String, dynamic>>[];

      // 1. Последние активации в магазине
      final sales = await _sb
          .from('sales')
          .select('user_id, step, created_at')
          .eq('shop_id', _storeId!)
          .order('created_at', ascending: false)
          .limit(15);

      for (final s in (sales as List)) {
        events.add({
          'type': 'activation',
          'icon': Icons.shopping_bag_rounded,
          'color': const Color(0xFF2E7BFF),
          'title': s['step'] == 1
              ? 'Новый клиент начал путь'
              : 'Повторное посещение (шаг ${s['step']})',
          'subtitle': 'Клиент активировал скидку',
          'time': DateTime.tryParse(s['created_at']?.toString() ?? '') ?? DateTime.now(),
        });
      }

      // 2. Подписки на магазин
      final subs = await _sb
          .from('user_progress')
          .select('user_id, last_active')
          .contains('subscribed_shops', [_storeId!])
          .order('last_active', ascending: false)
          .limit(10);

      for (final s in (subs as List)) {
        events.add({
          'type': 'subscribe',
          'icon': Icons.notifications_active_rounded,
          'color': Colors.orange,
          'title': 'Новая подписка',
          'subtitle': 'Клиент подписался на акции',
          'time': DateTime.tryParse(s['last_active']?.toString() ?? '') ?? DateTime.now(),
        });
      }

      // 3. Коллаборации с участием магазина
      final collabs = await _sb
          .from('active_collabs')
          .select('from_shop_id, to_shop_id, clicks, created_at')
          .or('from_shop_id.eq.$_storeId,to_shop_id.eq.$_storeId')
          .order('created_at', ascending: false)
          .limit(5);

      for (final c in (collabs as List)) {
        final isSource = c['from_shop_id'] == _storeId;
        events.add({
          'type': 'collab',
          'icon': Icons.link_rounded,
          'color': Colors.purple,
          'title': isSource
              ? 'Вы направляете клиентов в ${c['to_shop_id']}'
              : 'Партнёр ${c['from_shop_id']} направляет клиентов вам',
          'subtitle': 'Переходов: ${c['clicks'] ?? 0}',
          'time': DateTime.tryParse(c['created_at']?.toString() ?? '') ?? DateTime.now(),
        });
      }

      events.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));

      // Считаем подписчиков
      final subscribersAll = await _sb
          .from('user_progress')
          .select('user_id')
          .contains('subscribed_shops', [_storeId!]);

      if (mounted) {
        setState(() {
          _activity = events.take(12).toList();
          _subscribersCount = (subscribersAll as List).length;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadActivity: $e');
    }
  }

  Future<void> _loadAnnouncements() async {
    try {
      final data = await _sb
          .from('platform_announcements')
          .select()
          .eq('is_active', true)
          .order('priority', ascending: false)
          .order('created_at', ascending: false)
          .limit(5);
      if (mounted) {
        setState(() {
          _announcements = (data as List)
              .map((j) => Map<String, dynamic>.from(j))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('❌ _loadAnnouncements: $e');
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
            const Text('Не удалось определить ваш магазин.'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _sb.auth.signOut(),
              child: const Text('Выйти'),
            ),
          ],
        ),
      );
    }

    final priority = (_shopData['priority'] as num?)?.toInt() ?? 1;
    final shopName = _shopData['name'] ?? 'Мой магазин';
    final logoUrl = _shopData['image_url'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1300),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1000;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(shopName, logoUrl),
                  const SizedBox(height: 20),

                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildMainColumn(priority)),
                        const SizedBox(width: 20),
                        SizedBox(width: 320, child: _buildNewsSidebar()),
                      ],
                    )
                  else ...[
                    if (_announcements.isNotEmpty) ...[
                      _buildNewsBlock(),
                      const SizedBox(height: 20),
                    ],
                    _buildMainColumn(priority),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMainColumn(int priority) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTodayMetrics(),
        const SizedBox(height: 16),
        _buildQuickActionsBar(),
        const SizedBox(height: 20),
        if (_activity.isNotEmpty) ...[
          _buildActivityBlock(),
          const SizedBox(height: 20),
        ],
        _buildSettingsSection(priority),
      ],
    );
  }

  // ---------- Header ----------
    Widget _buildHeader(String shopName, String logoUrl) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          clipBehavior: Clip.antiAlias,
          child: logoUrl.isNotEmpty
              ? Image.network(
                  logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.store, size: 28, color: Colors.grey),
                )
              : const Icon(Icons.store, size: 28, color: Colors.grey),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      shopName,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        height: 1.1,
      ),
    ),
    const SizedBox(height: 2),
    Text(
      'Добро пожаловать!',
      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
    ),
  ],
),
        ),
        // Колокольчик с количеством новостей
        if (_announcements.isNotEmpty)
          Stack(
            children: [
              IconButton(
                onPressed: () => _showNewsDialog(context),
                icon: const Icon(Icons.notifications_none_rounded),
                tooltip: 'Новости ShopX',
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    '${_announcements.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _saveAllChanges,
          icon: const Icon(Icons.save_rounded, size: 18),
          label: const Text('Сохранить'),
        ),
      ],
    );
  }

    Widget _buildTodayMetrics() {
    final metrics = [
      {
        'value': '$_todayActivations',
        'label': 'Активаций',
        'color': const Color(0xFF2E7BFF),
      },
      {
        'value': '$_newClientsWeek',
        'label': 'Новых клиентов',
        'color': Colors.green,
      },
      {
        'value': '$_subscribersCount',
        'label': 'Подписчиков',
        'color': Colors.orange,
      },
      {
        'value': '—',
        'label': 'Конверсия',
        'color': Colors.purple,
      },
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Сегодня',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 500;
                if (isNarrow) {
                  return Wrap(
                    runSpacing: 16,
                    spacing: 24,
                    children: metrics.map((m) => _metricItem(m)).toList(),
                  );
                }
                return Row(
                  children: metrics
                      .map((m) => Expanded(child: _metricItem(m)))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricItem(Map<String, dynamic> m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          m['value'] as String,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: m['color'] as Color,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          m['label'] as String,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // ---------- Quick actions ----------
    Widget _buildQuickActionsBar() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _goToCalendar,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Создать акцию'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: const Color(0xFF2E7BFF),
              side: const BorderSide(color: Color(0xFF2E7BFF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _goToNotifications,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Отправить push'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: const Color(0xFF2E7BFF),
              side: const BorderSide(color: Color(0xFF2E7BFF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _goToStats,
            icon: const Icon(Icons.bar_chart_rounded, size: 18),
            label: const Text('Аналитика'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: const Color(0xFF2E7BFF),
              side: const BorderSide(color: Color(0xFF2E7BFF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Promo card ----------
  Widget _buildUpcomingPromotionCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7BFF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.event_available_rounded,
                      color: Color(0xFF2E7BFF), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Ближайшая акция',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: _goToCalendar,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Все акции', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_nearestPromotion == null)
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Нет активных акций. Создайте первую, чтобы привлечь клиентов.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nearestPromotion!['title'] ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_nearestPromotion!['discount']} — с ${DateFormat('dd.MM.yyyy').format(_nearestPromotion!['startDate'])} по ${DateFormat('dd.MM.yyyy').format(_nearestPromotion!['endDate'])}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ---------- Notification card ----------
  Widget _buildLastNotificationCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.notifications_active_rounded,
                      color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Последнее уведомление',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: _goToNotifications,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Все', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_lastNotification == null)
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Пока нет отправленных уведомлений.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lastNotification!['title'] ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _lastNotification!['body'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('dd.MM.yyyy HH:mm')
                        .format(_lastNotification!['timestamp']),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ---------- Priority card ----------
  Widget _buildPriorityCard(int priority) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.star_rounded, color: Colors.amber, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Приоритет в квестах',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7BFF).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$priority',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7BFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Чем выше приоритет, тем чаще магазин попадает в маршруты клиентов.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _onUpgradePriority,
              icon: const Icon(Icons.arrow_upward_rounded, size: 16),
              label: const Text('Повысить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(int priority) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Настройки магазина',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600)),
        ),
        _buildSettingsCard(
          title: 'Логотип и информация',
          icon: Icons.edit_rounded,
          child: Column(
            children: [
              _buildLogoEditor(),
              const SizedBox(height: 16),
              _buildInfoEditor(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildSettingsCard(
          title: 'Позиция на карте',
          icon: Icons.location_on_rounded,
          child: _buildMapPositionEditor(),
        ),
        const SizedBox(height: 12),
        _buildPriorityCard(priority),
      ],
    );
  }

  // ---------- Settings card ----------
  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7BFF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF2E7BFF), size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          children: [child],
        ),
      ),
    );
  }

  // ============================================================
  // Редакторы (без изменений)
  // ============================================================

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: const InputDecoration(hintText: ''),
        ),
      ],
    );
  }

    Widget _buildLogoEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Логотип для главного экрана',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              height: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _imageUrlController.text.isNotEmpty
                    ? Transform(
                        transform: _logoTransformController.value,
                        child: Image.network(_imageUrlController.text,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image))),
                      )
                    : Container(
                        color: Colors.grey[200], child: const Icon(Icons.image)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _labeledField(
                label: 'URL изображения',
                controller: _imageUrlController,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _openImageEditor(
                  title: 'Редактировать логотип',
                  controller: _logoTransformController,
                  imageUrl: _imageUrlController.text,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

    Widget _buildInfoEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Информация о магазине',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _labeledField(
          label: 'Название магазина',
          controller: _nameController,
        ),
        const SizedBox(height: 12),
        _labeledField(
          label: 'Описание',
          controller: _descriptionController,
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        _labeledField(
          label: 'Краткая скидка (для карточки)',
          controller: _shortDiscountController,
        ),
        const SizedBox(height: 12),
        _labeledField(
          label: 'Подробное описание акции',
          controller: _discountController,
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        const Text('Фото для подробной информации',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              height: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _infoImageUrlController.text.isNotEmpty
                    ? Transform(
                        transform: _infoImageTransformController.value,
                        child: Image.network(_infoImageUrlController.text,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image))),
                      )
                    : Container(
                        color: Colors.grey[200], child: const Icon(Icons.image)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _labeledField(
                label: 'URL фото',
                controller: _infoImageUrlController,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _openImageEditor(
                  title: 'Редактировать фото',
                  controller: _infoImageTransformController,
                  imageUrl: _infoImageUrlController.text,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

    Widget _buildMapPositionEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _labeledField(
                label: 'X (0.0 - 1.0)',
                controller: _mapXController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _labeledField(
                label: 'Y (0.0 - 1.0)',
                controller: _mapYController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _labeledField(
                label: 'Ширина',
                controller: _mapWidthController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _labeledField(
                label: 'Высота',
                controller: _mapHeightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
      ],
    );
  }
   // ---------- Объявления от ShopX ----------
    // Новости как отдельный блок (для узкого экрана)
  Widget _buildNewsBlock() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7BFF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.campaign_rounded,
                      color: Color(0xFF2E7BFF), size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Новости ShopX',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ..._announcements.take(2).map((a) => _newsItem(a)),
            if (_announcements.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton(
                  onPressed: () => _showNewsDialog(context),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Показать все (${_announcements.length})',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Новости как сайдбар (для широкого экрана)
  Widget _buildNewsSidebar() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7BFF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.campaign_rounded,
                      color: Color(0xFF2E7BFF), size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Новости ShopX',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            if (_announcements.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('Пока нет новостей',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12)),
                ),
              )
            else
              ..._announcements.map((a) => _newsItem(a)),
          ],
        ),
      ),
    );
  }

    Widget _newsItem(Map<String, dynamic> a) {
    // Парсим дату
    final createdAt = a['created_at'] != null
        ? DateTime.tryParse(a['created_at'].toString())
        : null;

    String dateLabel = '';
    if (createdAt != null) {
      final diff = DateTime.now().difference(createdAt);
      if (diff.inMinutes < 60) {
        dateLabel = '${diff.inMinutes} мин назад';
      } else if (diff.inHours < 24) {
        dateLabel = '${diff.inHours} ч назад';
      } else if (diff.inDays < 7) {
        dateLabel = '${diff.inDays} дн назад';
      } else {
        dateLabel = '${createdAt.day.toString().padLeft(2, '0')}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.year}';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a['icon'] ?? '📢', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a['title'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (dateLabel.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  a['body'] ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNewsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новости ShopX'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _announcements.map((a) => _newsItem(a)).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }


  // ---------- Лента активности ----------
  Widget _buildActivityBlock() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7BFF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.timeline_rounded,
                      color: Color(0xFF2E7BFF), size: 20),
                ),
                const SizedBox(width: 10),
                const Text('Лента активности',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  onPressed: _loadActivity,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'Обновить',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_activity.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Пока нет событий',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                ),
              )
            else
              ..._activity.map((e) {
                final color = e['color'] as Color;
                final time = e['time'] as DateTime;
                final diff = DateTime.now().difference(time);
                String timeLabel;
                if (diff.inMinutes < 1) {
                  timeLabel = 'только что';
                } else if (diff.inHours < 1) {
                  timeLabel = '${diff.inMinutes} мин назад';
                } else if (diff.inDays < 1) {
                  timeLabel = '${diff.inHours} ч назад';
                } else {
                  timeLabel = '${diff.inDays} дн назад';
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(e['icon'] as IconData,
                            color: color, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e['title'] as String,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(e['subtitle'] as String,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      Text(timeLabel,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  } 
}

// ======================================================================
// ВСПОМОГАТЕЛЬНЫЕ КЛАССЫ ДЛЯ РЕДАКТОРА ИЗОБРАЖЕНИЙ
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
            _imageSize =
                Size(info.image.width.toDouble(), info.image.height.toDouble());
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
    return Size(
        _frameScreenSize.width / _scale, _frameScreenSize.height / _scale);
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
                      builder: (context, constraints) =>
                          _buildEditor(constraints),
                    ),
                  ),
                  const SizedBox(width: 24),
                  _buildPreviewPanel(),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
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
                  painter: _OverlayPainter(
                      frameRect:
                          Rect.fromLTWH(frameLeft, frameTop, frameW, frameH)),
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
            child:
                SizedBox(width: pw, height: ph, child: _buildCropPreview(pw, ph)),
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
      canvas.drawLine(
          Offset(x, size.height), Offset(x + dashWidth, size.height), paint);
    }
    for (double y = 0; y < size.height; y += dashWidth + dashSpace) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dashWidth), paint);
      canvas.drawLine(
          Offset(size.width, y), Offset(size.width, y + dashWidth), paint);
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
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) =>
      oldDelegate.frameRect != frameRect;
}