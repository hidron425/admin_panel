import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'dart:async';

// ----------------------------------------------------------------------
// Модель BannerAd (локальная, чтобы не зависеть от других файлов)
// ----------------------------------------------------------------------
class BannerAd {
  final String id;
  final String title;
  final String description;
  final int color;
  final String targetShopId;
  final String discount;
  final String mallId;
  final String imageUrl;
  final List<double>? cropRectData;   // [left, top, width, height]
  final int priority;
  final bool isActive;

  BannerAd({
    required this.id,
    required this.title,
    required this.description,
    required this.color,
    required this.targetShopId,
    required this.discount,
    required this.mallId,
    this.imageUrl = '',
    this.cropRectData,
    this.priority = 0,
    this.isActive = true,
  });

  factory BannerAd.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    int colorInt = 0xFF6C63FF;
    final rawColor = data['color'];
    if (rawColor is int) {
      colorInt = rawColor;
    } else if (rawColor is String) {
      final hex = rawColor.replaceAll('#', '');
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) {
        colorInt = hex.length == 6 ? 0xFF000000 | parsed : parsed;
      }
    }

    return BannerAd(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      color: colorInt,
      targetShopId: data['targetShopId'] as String? ?? '',
      discount: data['discount'] as String? ?? '',
      mallId: data['mallId'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      cropRectData: (data['cropRect'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      priority: (data['priority'] as num?)?.toInt() ?? 0,
      isActive: data['isActive'] as bool? ?? true,
    );
  }
}

// ----------------------------------------------------------------------
// ЭКРАН УПРАВЛЕНИЯ БАННЕРАМИ
// ----------------------------------------------------------------------
class BannersScreen extends StatefulWidget {
  const BannersScreen({super.key});

  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends State<BannersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<BannerAd> _banners = [];
  List<BannerAd> _filteredBanners = [];
  Map<String, Map<String, dynamic>> _shopCache = {};
  bool _isLoading = true;
  String _sortBy = 'createdAt';
  bool _sortAsc = false;
  String? _hoveredId;

  @override
  void initState() {
    super.initState();
    _loadBanners();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBanners() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _firestore
          .collection('banners')
          .orderBy(_sortBy, descending: !_sortAsc)
          .get();
      final banners = snapshot.docs.map((doc) => BannerAd.fromFirestore(doc)).toList();
      await _preloadShops(banners);
      setState(() {
        _banners = banners;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Ошибка загрузки баннеров: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _preloadShops(List<BannerAd> banners) async {
    final Set<String> shopIds = {};
    for (final b in banners) {
      final sid = b.targetShopId;
      if (sid.isNotEmpty && !_shopCache.containsKey(sid)) {
        shopIds.add(sid);
      }
    }
    if (shopIds.isEmpty) return;
    final futures = shopIds.map((id) async {
      final doc = await _firestore.collection('shops').doc(id).get();
      if (doc.exists) {
        _shopCache[id] = doc.data()!;
        _shopCache[id]!['id'] = id;
      }
    });
    await Future.wait(futures);
  }

  void _onSearchChanged() => _applyFilter();

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredBanners = List.from(_banners);
    } else {
      _filteredBanners = _banners.where((b) {
        final title = b.title.toLowerCase();
        final desc = b.description.toLowerCase();
        final shopName = _getShopName(b.targetShopId).toLowerCase();
        return title.contains(query) || desc.contains(query) || shopName.contains(query);
      }).toList();
    }
    setState(() {});
  }

  String _getShopName(String? shopId) {
    if (shopId == null || shopId.isEmpty) return '';
    final shop = _shopCache[shopId];
    return shop != null ? (shop['name'] ?? '') : '';
  }

  void _changeSort(String field) {
    if (_sortBy == field) {
      _sortAsc = !_sortAsc;
    } else {
      _sortBy = field;
      _sortAsc = false;
    }
    _loadBanners();
  }

  Future<void> _deleteBanner(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить баннер?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _firestore.collection('banners').doc(id).delete();
      setState(() {
        _banners.removeWhere((b) => b.id == id);
        _applyFilter();
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Баннер удалён')));
    } catch (e) {
      debugPrint('❌ Ошибка удаления баннера: $e');
    }
  }

  Future<void> _toggleActive(String id, bool current) async {
    try {
      await _firestore.collection('banners').doc(id).update({'isActive': !current});
      setState(() {
        final idx = _banners.indexWhere((b) => b.id == id);
        if (idx != -1) {
          final old = _banners[idx];
          _banners[idx] = BannerAd(
            id: old.id,
            title: old.title,
            description: old.description,
            color: old.color,
            targetShopId: old.targetShopId,
            discount: old.discount,
            mallId: old.mallId,
            imageUrl: old.imageUrl,
            cropRectData: old.cropRectData,
            priority: old.priority,
            isActive: !current,
          );
          _applyFilter();
        }
      });
    } catch (e) {
      debugPrint('❌ Ошибка переключения: $e');
    }
  }

  void _openEditor({BannerAd? banner}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BannerEditorScreen(
          banner: banner,
          onSaved: _loadBanners,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        title: const Text('Управление баннерами', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Сортировка',
            onSelected: _changeSort,
            itemBuilder: (_) => [
              _sortItem('createdAt', 'По дате создания'),
              _sortItem('title', 'По названию'),
              _sortItem('priority', 'По приоритету'),
              _sortItem('discount', 'По скидке'),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Новый баннер'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск по названию, описанию, магазину…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear())
                    : null,
                filled: true,
                fillColor: const Color(0xFFF0F0F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
                : _filteredBanners.isEmpty
                    ? _buildEmptyState()
                    : _buildBannerGrid(),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Text(label),
          if (_sortBy == value) ...[
            const SizedBox(width: 6),
            Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: const Color(0xFF6C63FF)),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _banners.isEmpty ? 'Баннеров пока нет' : 'Ничего не найдено',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          Text(
            _banners.isEmpty ? 'Нажмите «Новый баннер», чтобы создать' : 'Измените запрос поиска',
            style: TextStyle(color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 3 : constraints.maxWidth > 600 ? 2 : 1;
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemCount: _filteredBanners.length,
          itemBuilder: (context, index) {
            final banner = _filteredBanners[index];
            return _BannerCard(
              banner: banner,
              shopName: _getShopName(banner.targetShopId),
              isHovered: _hoveredId == banner.id,
              onHover: (hovered) => setState(() => _hoveredId = hovered ? banner.id : null),
              onEdit: () => _openEditor(banner: banner),
              onDelete: () => _deleteBanner(banner.id),
              onToggle: () => _toggleActive(banner.id, banner.isActive),
            );
          },
        );
      },
    );
  }
}

// ----------------------------------------------------------------------
// _BannerCard (использует BannerAd)
// ----------------------------------------------------------------------
class _BannerCard extends StatelessWidget {
  final BannerAd banner;
  final String shopName;
  final bool isHovered;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggle;
  final ValueChanged<bool>? onHover;

  const _BannerCard({
    required this.banner,
    required this.shopName,
    required this.isHovered,
    this.onEdit,
    this.onDelete,
    this.onToggle,
    this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final title = banner.title.isNotEmpty ? banner.title : 'Без названия';
    final description = banner.description;
    final discount = banner.discount;
    final colorVal = banner.color;
    final imageUrl = banner.imageUrl;
    final isActive = banner.isActive;
    final priority = banner.priority;

    Widget imageWidget;
    if (imageUrl.isNotEmpty) {
      if (banner.cropRectData != null && banner.cropRectData!.length == 4) {
        final crop = Rect.fromLTWH(
          banner.cropRectData![0],
          banner.cropRectData![1],
          banner.cropRectData![2],
          banner.cropRectData![3],
        );
        imageWidget = Positioned.fill(
          child: BannerImagePreview(
            imageUrl: imageUrl,
            cropRect: crop,
            width: double.infinity,
            height: double.infinity,
          ),
        );
      } else {
        imageWidget = Positioned.fill(
          child: Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Color(colorVal))),
        );
      }
    } else {
      imageWidget = Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(colorVal), Color(colorVal).withOpacity(0.75)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => onHover?.call(true),
      onExit: (_) => onHover?.call(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: isHovered ? Matrix4.translationValues(0, -4, 0) : Matrix4.identity(),
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: isHovered ? 6 : 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              imageWidget,
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.65)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (discount.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                        child: Text(discount, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    const SizedBox(height: 6),
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(description, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                    if (shopName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.store_rounded, size: 14, color: Colors.white.withOpacity(0.7)),
                          const SizedBox(width: 4),
                          Flexible(child: Text(shopName, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (priority > 0)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.amber.shade600, borderRadius: BorderRadius.circular(10)),
                    child: Text('P$priority', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              if (isHovered)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(
                    children: [
                      _actionButton(icon: Icons.edit_rounded, color: Colors.white, bgColor: Colors.black.withOpacity(0.45), onTap: onEdit),
                      const SizedBox(width: 6),
                      _actionButton(icon: isActive ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white, bgColor: isActive ? Colors.orange.withOpacity(0.8) : Colors.green.withOpacity(0.8), onTap: onToggle),
                      const SizedBox(width: 6),
                      _actionButton(icon: Icons.delete_outline_rounded, color: Colors.white, bgColor: Colors.red.withOpacity(0.7), onTap: onDelete),
                    ],
                  ),
                ),
              if (!isActive)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(height: 4, color: Colors.red.shade400),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({required IconData icon, required Color color, required Color bgColor, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// BannerEditorScreen – редактор баннера
// ----------------------------------------------------------------------
class BannerEditorScreen extends StatefulWidget {
  final BannerAd? banner;
  final VoidCallback? onSaved;

  const BannerEditorScreen({super.key, this.banner, this.onSaved});

  @override
  State<BannerEditorScreen> createState() => _BannerEditorScreenState();
}

class _BannerEditorScreenState extends State<BannerEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _discountCtrl;
  late TextEditingController _imageUrlCtrl;
  late TextEditingController _shopSearchCtrl;

  Color _selectedColor = const Color(0xFF6C63FF);
  int _priority = 0;
  bool _isActive = true;
  Map<String, dynamic>? _selectedShop;
  List<Map<String, dynamic>> _shopResults = [];
  Timer? _debounce;
  bool _isSaving = false;
  bool get _isEditing => widget.banner != null;
  List<double>? _cropRectData;

  @override
  void initState() {
    super.initState();
    final b = widget.banner;
    _titleCtrl = TextEditingController(text: b?.title ?? '');
    _descCtrl = TextEditingController(text: b?.description ?? '');
    _discountCtrl = TextEditingController(text: b?.discount ?? '');
    _imageUrlCtrl = TextEditingController(text: b?.imageUrl ?? '');
    _shopSearchCtrl = TextEditingController();
    if (b?.color != null) _selectedColor = Color(b!.color);
    _priority = b?.priority ?? 0;
    _isActive = b?.isActive ?? true;
    _cropRectData = b?.cropRectData;
    _shopSearchCtrl.addListener(_onShopSearch);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _discountCtrl.dispose();
    _imageUrlCtrl.dispose();
    _shopSearchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onShopSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final query = _shopSearchCtrl.text.trim();
      if (query.length < 2) {
        setState(() => _shopResults.clear());
        return;
      }
      try {
        final snap = await _firestore
            .collection('shops')
            .where('name', isGreaterThanOrEqualTo: query)
            .where('name', isLessThanOrEqualTo: '$query\uf8ff')
            .limit(8)
            .get();
        setState(() {
          _shopResults = snap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }).toList();
        });
      } catch (_) {}
    });
  }

  Future<void> _saveBanner() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final data = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'discount': _discountCtrl.text.trim(),
      'color': _selectedColor.value,
      'priority': _priority,
      'imageUrl': _imageUrlCtrl.text.trim(),
      'isActive': _isActive,
      'cropRect': _cropRectData,
    };
    if (_selectedShop != null) {
      data['targetShopId'] = _selectedShop!['id'];
      data['shopName'] = _selectedShop!['name'];
    } else if (_isEditing) {
      data['targetShopId'] = widget.banner!.targetShopId;
    }
    try {
      if (_isEditing) {
        await _firestore.collection('banners').doc(widget.banner!.id).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('banners').add(data);
      }
      widget.onSaved?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEditing ? 'Баннер обновлён' : 'Баннер создан')));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Ошибка сохранения: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка сохранения')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickColor() async {
    final color = await showColorPickerDialog(context, _selectedColor);
    if (color != null) setState(() => _selectedColor = color);
  }

  Future<void> _openImageEditor() async {
    if (_imageUrlCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вставьте URL изображения')));
      return;
    }
    final result = await Navigator.push<Rect>(
      context,
      MaterialPageRoute(
        builder: (_) => _ImageEditorDialog(
          title: 'Редактировать изображение баннера',
          imageUrl: _imageUrlCtrl.text.trim(),
          iconWidth: 320,
          iconHeight: 160,
          fullScreen: true,
          initialCrop: _cropRectData != null && _cropRectData!.length == 4
              ? Rect.fromLTWH(_cropRectData![0], _cropRectData![1], _cropRectData![2], _cropRectData![3])
              : null,
        ),
      ),
    );
    if (result != null && result != Rect.zero) {
      setState(() => _cropRectData = [result.left, result.top, result.width, result.height]);
    }
  }

  // ======================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ UI ========================
  Widget _sectionTitle(String text) {
    return Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54, letterSpacing: 0.5));
  }

  Widget _buildTextField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (v) {
        if (controller == _titleCtrl && (v == null || v.trim().isEmpty)) return 'Название обязательно';
        return null;
      },
    );
  }

  Widget _buildShopSelector() {
    return Column(
      children: [
        if (_selectedShop != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.store_rounded, color: Color(0xFF6C63FF)),
                const SizedBox(width: 8),
                Expanded(child: Text(_selectedShop!['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                GestureDetector(
                  onTap: () => setState(() { _selectedShop = null; _shopSearchCtrl.clear(); }),
                  child: const Icon(Icons.close, size: 20, color: Colors.grey),
                ),
              ],
            ),
          ),
        if (_selectedShop == null)
          TextFormField(
            controller: _shopSearchCtrl,
            decoration: InputDecoration(
              hintText: 'Начните вводить название магазина…',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        if (_shopResults.isNotEmpty && _selectedShop == null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _shopResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, i) {
                final shop = _shopResults[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.store_rounded, size: 20),
                  title: Text(shop['name'] ?? ''),
                  onTap: () {
                    setState(() {
                      _selectedShop = shop;
                      _shopSearchCtrl.text = shop['name'] ?? '';
                      _shopResults.clear();
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildColorPicker() {
    return GestureDetector(
      onTap: _pickColor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _selectedColor,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _selectedColor.withOpacity(0.4), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 10),
            const Text('Цвет баннера'),
            const Spacer(),
            Text(
              '#${_selectedColor.value.toRadixString(16).substring(2).toUpperCase()}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Text('Приоритет'),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _priority > 0 ? () => setState(() => _priority--) : null,
          ),
          Text('$_priority', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => setState(() => _priority++),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final previewBanner = BannerAd(
      id: '',
      title: _titleCtrl.text.isNotEmpty ? _titleCtrl.text : 'Название',
      description: _descCtrl.text.isNotEmpty ? _descCtrl.text : 'Описание баннера',
      discount: _discountCtrl.text,
      color: _selectedColor.value,
      targetShopId: '',
      mallId: '',
      imageUrl: _imageUrlCtrl.text.trim(),
      cropRectData: _cropRectData,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Предпросмотр'),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 170,
            child: _BannerItemPreview(banner: previewBanner),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        title: Text(_isEditing ? 'Редактировать баннер' : 'Новый баннер'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveBanner,
            icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
            label: const Text('Сохранить'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPreview(),
              const SizedBox(height: 24),
              _sectionTitle('Основное'),
              const SizedBox(height: 8),
              _buildTextField(_titleCtrl, 'Название баннера'),
              const SizedBox(height: 12),
              _buildTextField(_descCtrl, 'Краткое описание', maxLines: 2),
              const SizedBox(height: 12),
              _buildTextField(_discountCtrl, 'Текст скидки (необязательно)'),
              const SizedBox(height: 24),
              _sectionTitle('Привязать к магазину'),
              const SizedBox(height: 8),
              _buildShopSelector(),
              const SizedBox(height: 24),
              _sectionTitle('Изображение'),
              const SizedBox(height: 8),
              _buildTextField(_imageUrlCtrl, 'URL изображения'),
              const SizedBox(height: 8),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _imageUrlCtrl.text.trim().isNotEmpty ? _openImageEditor : null,
                  icon: const Icon(Icons.edit),
                  label: const Text('Редактировать изображение'),
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle('Оформление'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildColorPicker()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildPrioritySelector()),
                ],
              ),
              const SizedBox(height: 24),
              _sectionTitle('Статус'),
              const SizedBox(height: 8),
              Card(
                child: SwitchListTile(
                  title: const Text('Баннер активен'),
                  subtitle: Text(_isActive ? 'Отображается пользователям' : 'Скрыт от пользователей'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// _BannerItemPreview – заглушка для предпросмотра в редакторе
// ----------------------------------------------------------------------
class _BannerItemPreview extends StatelessWidget {
  final BannerAd banner;
  const _BannerItemPreview({required this.banner});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (banner.imageUrl.isNotEmpty)
          Positioned.fill(
            child: banner.cropRectData != null && banner.cropRectData!.length == 4
                ? BannerImagePreview(
                    imageUrl: banner.imageUrl,
                    cropRect: Rect.fromLTWH(
                      banner.cropRectData![0],
                      banner.cropRectData![1],
                      banner.cropRectData![2],
                      banner.cropRectData![3],
                    ),
                    width: double.infinity,
                    height: double.infinity,
                  )
                : Image.network(banner.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Color(banner.color))),
          )
        else
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(banner.color), Color(banner.color).withOpacity(0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        if (banner.imageUrl.isNotEmpty)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black.withOpacity(0.55), Colors.black.withOpacity(0.12)],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (banner.discount.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(20)),
                        child: Text(banner.discount, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    if (banner.discount.isNotEmpty) const SizedBox(height: 8),
                    Text(
                      banner.title.isNotEmpty ? banner.title : 'Баннер',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    if (banner.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        banner.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// _ImageEditorDialog – редактор изображения баннера
// ----------------------------------------------------------------------
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
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  late double _frameAspect = widget.iconWidth / widget.iconHeight;
  Size _frameScreenSize = Size.zero;
  Offset _lastFocal = Offset.zero;
  double _lastScale = 1.0;
  Offset _lastOffset = Offset.zero;
  bool _initApplied = false;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  void _loadImageSize() {
    if (widget.imageUrl.isEmpty) return;
    final image = Image.network(widget.imageUrl);
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (!mounted) return;
        setState(() {
          _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
          if (!_initApplied) _applyInitialCropIfNeeded();
        });
      }),
    );
  }

  void _applyInitialCropIfNeeded() {
    if (_imageSize == null || _frameScreenSize == Size.zero) return;
    _initApplied = true;

    if (widget.initialCrop != null && !widget.initialCrop!.isEmpty) {
      final crop = widget.initialCrop!;
      _scale = _frameScreenSize.width / crop.width;
      _offset = Offset(crop.left, crop.top);
    } else {
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
    }
    _clampOffset();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            tooltip: 'Авто (вписать картинку)',
            icon: const Icon(Icons.fit_screen),
            onPressed: _imageSize == null ? null : () => setState(() {
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
            }),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _cropRectInImage()),
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
        _lastOffset = _offset;
      },
      onScaleUpdate: (details) {
        setState(() {
          final newScale = (_lastScale * details.scale).clamp(0.05, 10.0);
          final delta = details.localFocalPoint - _lastFocal;
          _lastFocal = details.localFocalPoint;
          _scale = newScale;
          _offset = Offset(
            _offset.dx - delta.dx / _lastScale,
            _offset.dy - delta.dy / _lastScale,
          );
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
    const double previewW = 200;
    final previewH = previewW / _frameAspect;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Предпросмотр', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: previewW, height: previewH, child: _buildCropPreview(previewW, previewH)),
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
        minWidth: 0, minHeight: 0, maxWidth: double.infinity, maxHeight: double.infinity,
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

// ----------------------------------------------------------------------
// Рисовальщики
// ----------------------------------------------------------------------
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
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(frameRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => oldDelegate.frameRect != frameRect;
}

// ----------------------------------------------------------------------
// Диалог выбора цвета
// ----------------------------------------------------------------------
Future<Color?> showColorPickerDialog(BuildContext context, Color current) {
  final presetColors = [
    0xFF6C63FF, 0xFFFF6B6B, 0xFF4ECDC4, 0xFFFFD93D, 0xFFFF8C42,
    0xFF45B7D1, 0xFF96CEB4, 0xFFFF69B4, 0xFF7B68EE, 0xFF20B2AA,
    0xFFDC143C, 0xFF2E4057,
  ];

  return showDialog<Color>(
    context: context,
    builder: (ctx) {
      Color selected = current;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Выберите цвет'),
            content: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: presetColors.map((c) {
                final color = Color(c);
                final isSelected = selected.value == c;
                return GestureDetector(
                  onTap: () => setDialogState(() => selected = color),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: Colors.black87, width: 3) : null,
                      boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                  ),
                );
              }).toList(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Выбрать')),
            ],
          );
        },
      );
    },
  );
}

// ----------------------------------------------------------------------
// BannerImagePreview – универсальный виджет для обрезки (используется и в админке, и в клиенте)
// ----------------------------------------------------------------------
class BannerImagePreview extends StatelessWidget {
  final String imageUrl;
  final Rect? cropRect;
  final double width;
  final double height;

  const BannerImagePreview({
    required this.imageUrl,
    required this.cropRect,
    required this.width,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (cropRect == null || cropRect!.isEmpty || cropRect!.width == 0) {
      return Image.network(imageUrl, fit: BoxFit.cover, width: width, height: height);
    }
    final crop = cropRect!;
    final scaleX = width / crop.width;
    final scaleY = height / crop.height;
    final scale = math.min(scaleX, scaleY);
    final offsetX = -crop.left * scale;
    final offsetY = -crop.top * scale;
    return ClipRect(
      child: Transform.translate(
        offset: Offset(offsetX, offsetY),
        child: Transform.scale(
          scale: scale,
          child: Image.network(imageUrl, fit: BoxFit.cover, width: width, height: height),
        ),
      ),
    );
  }
}