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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Добро пожаловать!',
                        style: TextStyle(fontSize: 18, color: Colors.grey)),
                    Text(shopName,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _saveAllChanges,
                icon: const Icon(Icons.save),
                label: const Text('Сохранить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _buildInfoCard(
            icon: Icons.trending_up,
            title: 'Быстрая статистика',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Активации сегодня', _todayActivations.toString()),
                _buildStatItem('Новые клиенты за неделю', _newClientsWeek.toString()),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _buildQuickActions(),
          const SizedBox(height: 24),

          _buildSettingsCard(
            title: 'Логотип и информация',
            icon: Icons.edit,
            child: Column(
              children: [
                _buildLogoEditor(),
                const SizedBox(height: 16),
                _buildInfoEditor(),
              ],
            ),
          ),

          const SizedBox(height: 16),

          _buildSettingsCard(
            title: 'Позиция на карте',
            icon: Icons.location_on,
            child: _buildMapPositionEditor(),
          ),

          const SizedBox(height: 16),

          _buildInfoCard(
            icon: Icons.calendar_today,
            title: 'Ближайшая акция',
            child: _nearestPromotion == null
                ? const Text('Нет активных акций.', style: TextStyle(color: Colors.grey))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_nearestPromotion!['title'],
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                          '${_nearestPromotion!['discount']} — с ${DateFormat('dd.MM.yyyy').format(_nearestPromotion!['startDate'])} по ${DateFormat('dd.MM.yyyy').format(_nearestPromotion!['endDate'])}'),
                    ],
                  ),
            trailing: TextButton(
              onPressed: _goToCalendar,
              child: const Text('Все акции'),
            ),
          ),

          const SizedBox(height: 16),

          _buildInfoCard(
            icon: Icons.notifications,
            title: 'Последнее уведомление',
            child: _lastNotification == null
                ? const Text('Нет уведомлений.', style: TextStyle(color: Colors.grey))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_lastNotification!['title'],
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_lastNotification!['body'],
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                          DateFormat('dd.MM.yyyy HH:mm').format(_lastNotification!['timestamp']),
                          style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
            trailing: TextButton(
              onPressed: _goToNotifications,
              child: const Text('Все уведомления'),
            ),
          ),

          const SizedBox(height: 16),

          _buildInfoCard(
            icon: Icons.star,
            title: 'Приоритет',
            child: Row(
              children: [
                Chip(label: Text('$priority'), backgroundColor: Colors.blue.shade100),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      'Чем выше приоритет, тем чаще ваши акции предлагаются пользователям.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ),
              ],
            ),
            trailing: ElevatedButton.icon(
              onPressed: _onUpgradePriority,
              icon: const Icon(Icons.trending_up),
              label: const Text('Повысить'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF6C63FF)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      {'icon': Icons.calendar_month, 'title': 'Акции', 'onTap': _goToCalendar},
      {'icon': Icons.bar_chart, 'title': 'Статистика', 'onTap': _goToStats},
      {'icon': Icons.notifications, 'title': 'Уведомления', 'onTap': _goToNotifications},
    ];

    return Row(
      children: actions.map((action) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: InkWell(
                onTap: action['onTap'] as VoidCallback,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Icon(action['icon'] as IconData,
                          size: 28, color: const Color(0xFF6C63FF)),
                      const SizedBox(height: 8),
                      Text(action['title'] as String, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        leading: Icon(icon, color: const Color(0xFF6C63FF)),
        title: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
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
              child: TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(
                    labelText: 'URL изображения', border: OutlineInputBorder()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _openImageEditor(
                title: 'Редактировать логотип',
                controller: _logoTransformController,
                imageUrl: _imageUrlController.text,
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
        const Text('Информация о магазине', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Название магазина')),
        const SizedBox(height: 12),
        TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Описание')),
        const SizedBox(height: 12),
        TextFormField(
            controller: _shortDiscountController,
            decoration: const InputDecoration(labelText: 'Краткая скидка (для карточки)')),
        const SizedBox(height: 12),
        TextFormField(
            controller: _discountController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Подробное описание акции')),
        const SizedBox(height: 12),
        const Text('Фото для подробной информации',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
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
              child: TextFormField(
                controller: _infoImageUrlController,
                decoration: const InputDecoration(
                    labelText: 'URL фото', border: OutlineInputBorder()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _openImageEditor(
                title: 'Редактировать фото',
                controller: _infoImageTransformController,
                imageUrl: _infoImageUrlController.text,
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
          children: [
            Expanded(
              child: TextFormField(
                controller: _mapXController,
                decoration: const InputDecoration(
                    labelText: 'X (0.0 - 1.0)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _mapYController,
                decoration: const InputDecoration(
                    labelText: 'Y (0.0 - 1.0)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                decoration: const InputDecoration(
                    labelText: 'Ширина', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _mapHeightController,
                decoration: const InputDecoration(
                    labelText: 'Высота', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
      ],
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
                  painter: _OverlayPainter(
                      frameRect: Rect.fromLTWH(frameLeft, frameTop, frameW, frameH)),
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