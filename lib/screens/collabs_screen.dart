import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:admin_panel/utils/audit.dart';
import 'package:admin_panel/utils/app_state.dart';

class CollabsScreen extends StatefulWidget {
  const CollabsScreen({Key? key}) : super(key: key);

  @override
  State<CollabsScreen> createState() => _CollabsScreenState();
}

class _CollabsScreenState extends State<CollabsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  String? _currentShopId;
  String? _selectedMallId;
  List<String> _mallShopIds = [];

  List<Map<String, dynamic>> _activeCollabs = [];
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _offers = [];
  Set<String> _acceptedOfferIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedMallId = AppState.selectedMallId.value;
    AppState.selectedMallId.addListener(_onMallChanged);
    _init();
  }

  @override
  void dispose() {
    AppState.selectedMallId.removeListener(_onMallChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onMallChanged() {
    if (_selectedMallId != AppState.selectedMallId.value) {
      setState(() {
        _selectedMallId = AppState.selectedMallId.value;
        _mallShopIds = [];
      });
      _init();
    }
  }

  Future<void> _init() async {
    await _loadCurrentShopId();
    await _loadMallShops();
    await _loadAllData();
  }

  Future<void> _loadCurrentShopId() async {
    try {
      final email = supa.Supabase.instance.client.auth.currentUser?.email;
      if (email != null) {
        final data = await _sb
            .from('user_metadata')
            .select('store_id')
            .eq('email', email)
            .maybeSingle();
        if (mounted) {
          setState(() => _currentShopId = data?['store_id'] as String?);
        }
      }
    } catch (e) {
      debugPrint('❌ _loadCurrentShopId: $e');
    }
  }

  Future<void> _loadMallShops() async {
    if (_selectedMallId == null) {
      if (mounted) setState(() => _mallShopIds = []);
      return;
    }
    try {
      final data = await _sb
          .from('shops')
          .select('firestore_id')
          .eq('mall_id', _selectedMallId!);
      if (mounted) {
        setState(() {
          _mallShopIds = (data as List)
              .map((j) => j['firestore_id'] as String)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('❌ _loadMallShops: $e');
    }
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    try {
      final active = await _sb.from('active_collabs').select();
      final suggested = await _sb
          .from('suggested_collabs')
          .select()
          .eq('status', 'pending');
      final offers = await _sb
          .from('auction_offers')
          .select()
          .eq('status', 'active')
          .order('created_at', ascending: false);

      Set<String> accepted = {};
      if (_currentShopId != null) {
        final myCollabs = await _sb
            .from('active_collabs')
            .select('offer_id')
            .eq('from_shop_id', _currentShopId!);
        accepted = (myCollabs as List)
            .map((j) => j['offer_id']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet();
      }

      if (mounted) {
        setState(() {
          _activeCollabs = (active as List)
              .map((j) => Map<String, dynamic>.from(j))
              .where(_belongsToSelectedMall)
              .toList();
          _suggestions = (suggested as List)
              .map((j) => Map<String, dynamic>.from(j))
              .where(_belongsToSelectedMall)
              .toList();
          _offers = (offers as List)
              .map((j) => Map<String, dynamic>.from(j))
              .where((o) {
                if (_selectedMallId == null) return true;
                final shopId = o['shop_id'] as String? ?? '';
                return _mallShopIds.contains(shopId);
              })
              .toList();
          _acceptedOfferIds = accepted;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadAllData: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _belongsToSelectedMall(Map<String, dynamic> data) {
    if (_selectedMallId == null) return true;
    final fromId = data['from_shop_id'] as String? ?? '';
    final toId = data['to_shop_id'] as String? ?? '';
    return _mallShopIds.contains(fromId) || _mallShopIds.contains(toId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedMallId == null
            ? 'Коллаборации (Все ТЦ)'
            : 'Коллаборации (${_selectedMallId})'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Активные'),
            Tab(text: 'Предложения (авто)'),
            Tab(text: 'Аукцион (оферты)'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActiveCollabsTab(),
                _buildSuggestionsTab(),
                _buildOpenMarketTab(),
              ],
            ),
      floatingActionButton: _currentShopId != null
          ? FloatingActionButton(
              onPressed: () => _showCreateOfferDialog(),
              tooltip: 'Создать оферту',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildActiveCollabsTab() {
    if (_activeCollabs.isEmpty) {
      return const Center(child: Text('Нет активных коллабораций'));
    }
    return ListView.builder(
      itemCount: _activeCollabs.length,
      itemBuilder: (context, index) {
        final data = _activeCollabs[index];
        final fromId = data['from_shop_id'] ?? '';
        final toId = data['to_shop_id'] ?? '';
        final expiresRaw = data['expires'] as String?;
        final expires = expiresRaw != null ? DateTime.tryParse(expiresRaw) : null;
        final clicks = data['clicks'] ?? 0;
        final bid = data['bid'] ?? 0;
        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: Text('$fromId → $toId'),
            subtitle: Text(
                'Ставка: $bid руб./переход | Истекает: ${expires?.toLocal().toString().split(' ')[0] ?? 'нет'} | Переходов: $clicks'),
            trailing: (fromId == _currentShopId || toId == _currentShopId)
                ? IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteActiveCollab(data['id'].toString()),
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _deleteActiveCollab(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить коллаборацию?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _sb.from('active_collabs').delete().eq('id', docId);
        AuditLogger.log(action: 'delete', collection: 'active_collabs', docId: docId);
        _loadAllData();
      } catch (e) {
        debugPrint('❌ _deleteActiveCollab: $e');
      }
    }
  }

  Widget _buildSuggestionsTab() {
    if (_suggestions.isEmpty) {
      return const Center(child: Text('Нет новых предложений'));
    }
    return ListView.builder(
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final data = _suggestions[index];
        final fromId = data['from_shop_id'] ?? '';
        final toId = data['to_shop_id'] ?? '';
        final rate = data['rate'] ?? 0;
        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: Text('$fromId → $toId'),
            subtitle: Text('Частота: $rate переходов за 30 дней'),
            trailing: ElevatedButton(
              onPressed: () => _acceptSuggestion(data['id'].toString(), fromId, toId),
              child: const Text('Принять'),
            ),
          ),
        );
      },
    );
  }

  Future<void> _acceptSuggestion(String suggestionId, String fromShopId, String toShopId) async {
    try {
      await _sb.from('active_collabs').insert({
        'from_shop_id': fromShopId,
        'to_shop_id': toShopId,
        'expires': DateTime.now().add(const Duration(days: 90)).toIso8601String(),
        'clicks': 0,
        'type': 'auto_suggestion',
        'created_at': DateTime.now().toIso8601String(),
      });
      await _sb.from('suggested_collabs').update({'status': 'accepted'}).eq('id', suggestionId);
      AuditLogger.log(
        action: 'accept_suggestion',
        collection: 'suggested_collabs',
        docId: suggestionId,
        changes: {'from_shop_id': fromShopId, 'to_shop_id': toShopId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Коллаборация активирована')));
      }
      _loadAllData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Widget _buildOpenMarketTab() {
    if (_offers.isEmpty) {
      return const Center(child: Text('Нет активных оферт'));
    }
    return ListView.builder(
      itemCount: _offers.length,
      itemBuilder: (context, index) {
        final data = _offers[index];
        final offerId = data['id'].toString();
        final targetShopId = data['shop_id'] ?? '';
        final bid = data['bid'] ?? 0;
        final budget = data['budget'] ?? 0;
        final remaining = data['remaining_budget'] ?? budget;
        final targetCategory = data['target_category'] ?? 'любая';
        final expiresRaw = data['expires'] as String?;
        final expires = expiresRaw != null ? DateTime.tryParse(expiresRaw) : null;
        final isOwnOffer = targetShopId == _currentShopId;
        final alreadyAccepted = _acceptedOfferIds.contains(offerId);

        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: Text(
              isOwnOffer
                  ? 'ВАША ОФЕРТА: Магазин $targetShopId платит $bid ₽/переход'
                  : 'Магазин $targetShopId платит $bid ₽/переход',
              style: isOwnOffer
                  ? const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)
                  : null,
            ),
            subtitle: Text(
                'Остаток: $remaining / $budget ₽ | Категория: $targetCategory | До: ${expires?.toLocal().toString().split(' ')[0] ?? 'не ограничено'}'),
            trailing: isOwnOffer
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        onPressed: () => _editOffer(offerId, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteOffer(offerId),
                      ),
                    ],
                  )
                : alreadyAccepted
                    ? const Chip(label: Text('Уже источник'), backgroundColor: Colors.grey)
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.trending_up),
                        label: const Text('Стать источником'),
                        onPressed: () => _acceptOffer(offerId, targetShopId, bid),
                      ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateOfferDialog() async {
    final bidCtrl = TextEditingController();
    final budgetCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    DateTime expires = DateTime.now().add(const Duration(days: 30));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Создать аукционную оферту'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ваш магазин: $_currentShopId', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: bidCtrl,
                  decoration: const InputDecoration(labelText: 'Ставка (руб./переход)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: budgetCtrl,
                  decoration: const InputDecoration(labelText: 'Общий бюджет (руб.)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Категория источника (пусто – любая)'),
                ),
                ListTile(
                  title: const Text('Действует до'),
                  subtitle: Text(expires.toLocal().toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: expires,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setDialogState(() => expires = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final bid = int.tryParse(bidCtrl.text);
                final budget = int.tryParse(budgetCtrl.text);
                if (bid == null || budget == null || bid <= 0 || budget <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ставка и бюджет должны быть положительными')),
                  );
                  return;
                }
                final data = <String, dynamic>{
                  'shop_id': _currentShopId,
                  'bid': bid,
                  'budget': budget,
                  'remaining_budget': budget,
                  'target_category': categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim(),
                  'status': 'active',
                  'expires': expires.toIso8601String(),
                  'created_at': DateTime.now().toIso8601String(),
                  'mall_id': _selectedMallId,
                };
                try {
                  final result = await _sb.from('auction_offers').insert(data).select('id').single();
                  AuditLogger.log(
                    action: 'create',
                    collection: 'auction_offers',
                    docId: result['id'].toString(),
                    changes: data,
                  );
                  if (mounted) Navigator.pop(ctx);
                  _loadAllData();
                } catch (e) {
                  debugPrint('❌ create offer: $e');
                }
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editOffer(String offerId, Map<String, dynamic> current) async {
    final bidCtrl = TextEditingController(text: current['bid'].toString());
    final budgetCtrl = TextEditingController(text: current['budget'].toString());
    final categoryCtrl = TextEditingController(text: current['target_category'] ?? '');
    final expiresRaw = current['expires'] as String?;
    DateTime expires = expiresRaw != null ? DateTime.parse(expiresRaw) : DateTime.now().add(const Duration(days: 30));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Редактировать оферту'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: bidCtrl, decoration: const InputDecoration(labelText: 'Ставка (руб./переход)'), keyboardType: TextInputType.number),
                TextField(controller: budgetCtrl, decoration: const InputDecoration(labelText: 'Общий бюджет (руб.)'), keyboardType: TextInputType.number),
                TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Категория источника')),
                ListTile(
                  title: const Text('Действует до'),
                  subtitle: Text(expires.toLocal().toString().split(' ')[0]),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: expires,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setDialogState(() => expires = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final bid = int.tryParse(bidCtrl.text);
                final budget = int.tryParse(budgetCtrl.text);
                if (bid == null || budget == null || bid <= 0 || budget <= 0) return;
                final data = {
                  'bid': bid,
                  'budget': budget,
                  'remaining_budget': budget,
                  'target_category': categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim(),
                  'expires': expires.toIso8601String(),
                };
                try {
                  await _sb.from('auction_offers').update(data).eq('id', offerId);
                  AuditLogger.log(action: 'update', collection: 'auction_offers', docId: offerId, changes: data);
                  if (mounted) Navigator.pop(ctx);
                  _loadAllData();
                } catch (e) {
                  debugPrint('❌ edit offer: $e');
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteOffer(String offerId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить оферту?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _sb.from('auction_offers').delete().eq('id', offerId);
        AuditLogger.log(action: 'delete', collection: 'auction_offers', docId: offerId);
        _loadAllData();
      } catch (e) {
        debugPrint('❌ delete offer: $e');
      }
    }
  }

  Future<void> _acceptOffer(String offerId, String targetShopId, int bid) async {
    if (_currentShopId == null) return;

    try {
      final currentShop = await _sb
          .from('shops')
          .select('category')
          .eq('firestore_id', _currentShopId!)
          .maybeSingle();
      if (currentShop == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ваш магазин не найден')));
        }
        return;
      }
      final currentCategory = currentShop['category'] as String?;

      final offer = await _sb
          .from('auction_offers')
          .select()
          .eq('id', offerId)
          .maybeSingle();
      if (offer == null) return;

      final requiredCategory = offer['target_category'] as String?;
      if (requiredCategory != null &&
          requiredCategory.isNotEmpty &&
          currentCategory != requiredCategory) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Требуется категория "$requiredCategory", у вас "$currentCategory"'),
          ));
        }
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Стать источником трафика?'),
          content: Text(
              'Вы направляете посетителей в $targetShopId. Получаете $bid руб. за переход.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да, создать')),
          ],
        ),
      );
      if (confirm != true) return;

      final collabData = {
        'from_shop_id': _currentShopId,
        'to_shop_id': targetShopId,
        'expires': DateTime.now().add(const Duration(days: 90)).toIso8601String(),
        'clicks': 0,
        'bid': bid,
        'type': 'auction_response',
        'offer_id': offerId,
        'created_at': DateTime.now().toIso8601String(),
      };
      final collabResult = await _sb.from('active_collabs').insert(collabData).select('id').single();
      AuditLogger.log(
        action: 'create',
        collection: 'active_collabs',
        docId: collabResult['id'].toString(),
        changes: collabData,
      );

      final offerUpdate = {
        'status': 'taken',
        'taken_by': _currentShopId,
        'taken_at': DateTime.now().toIso8601String(),
      };
      await _sb.from('auction_offers').update(offerUpdate).eq('id', offerId);
      AuditLogger.log(action: 'update', collection: 'auction_offers', docId: offerId, changes: offerUpdate);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Коллаборация создана!')),
        );
      }
      _loadAllData();
    } catch (e) {
      debugPrint('❌ _acceptOffer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }
}