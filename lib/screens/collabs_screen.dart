import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:admin_panel/utils/audit.dart';   // 🆕 сервис аудита

class CollabsScreen extends StatefulWidget {
  const CollabsScreen({Key? key}) : super(key: key);

  @override
  State<CollabsScreen> createState() => _CollabsScreenState();
}

class _CollabsScreenState extends State<CollabsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  String? _currentShopId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _getCurrentShopId();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentShopId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      final doc = await _firestore.collection('users').doc(user.email!).get();
      if (mounted) {
        setState(() {
          _currentShopId = doc.data()?['storeId'] as String?;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentShopId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Коллаборации'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Активные'),
            Tab(text: 'Предложения (авто)'),
            Tab(text: 'Аукцион (оферты)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveCollabsTab(),
          _buildSuggestionsTab(),
          _buildOpenMarketTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateOfferDialog(),
        child: const Icon(Icons.add),
        tooltip: 'Создать оферту',
      ),
    );
  }

  // ==================== ВКЛАДКА 1: АКТИВНЫЕ КОЛЛАБОРАЦИИ ====================
  Widget _buildActiveCollabsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('active_collabs').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Ошибка: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('Нет активных коллабораций'));
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final fromId = data['fromShopId'] ?? '';
            final toId = data['toShopId'] ?? '';
            final expires = (data['expires'] as Timestamp?)?.toDate();
            final clicks = data['clicks'] ?? 0;
            final bid = data['bid'] ?? 0;
            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text('$fromId → $toId'),
                subtitle: Text('Ставка: $bid руб./переход | Истекает: ${expires?.toLocal().toString().split(' ')[0] ?? 'нет'} | Переходов: $clicks'),
                trailing: (fromId == _currentShopId || toId == _currentShopId)
                    ? IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteActiveCollab(doc.id),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteActiveCollab(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить коллаборацию?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('active_collabs').doc(docId).delete();
      // 🆕 Аудит удаления коллаборации
      AuditLogger.log(
        action: 'delete',
        collection: 'active_collabs',
        docId: docId,
      );
    }
  }

  // ==================== ВКЛАДКА 2: ПРЕДЛОЖЕНИЯ (АВТО) ====================
  Widget _buildSuggestionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('suggested_collabs')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Ошибка: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('Нет новых предложений'));
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final fromId = data['fromShopId'] ?? '';
            final toId = data['toShopId'] ?? '';
            final rate = data['rate'] ?? 0;
            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text('$fromId → $toId'),
                subtitle: Text('Частота: $rate переходов за 30 дней'),
                trailing: ElevatedButton(
                  onPressed: () => _acceptSuggestion(doc.id, fromId, toId),
                  child: const Text('Принять'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _acceptSuggestion(String suggestionId, String fromShopId, String toShopId) async {
    try {
      final callable = _functions.httpsCallable('acceptCollabSuggestion');
      await callable.call({
        'suggestionId': suggestionId,
        'fromShopId': fromShopId,
        'toShopId': toShopId,
      });
      // 🆕 Аудит принятия предложения (Cloud Function меняет данные, но действие инициировано админом)
      AuditLogger.log(
        action: 'accept_suggestion',
        collection: 'suggested_collabs',
        docId: suggestionId,
        changes: {'fromShopId': fromShopId, 'toShopId': toShopId},
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Коллаборация активирована')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  // ==================== ВКЛАДКА 3: АУКЦИОН (ОФЕРТЫ) ====================
  Widget _buildOpenMarketTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('auction_offers')
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Ошибка: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('Нет активных оферт'));

        return FutureBuilder<QuerySnapshot>(
          future: _firestore.collection('active_collabs')
              .where('fromShopId', isEqualTo: _currentShopId)
              .get(),
          builder: (context, collabSnapshot) {
            if (collabSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final existingCollabs = collabSnapshot.data?.docs ?? [];
            final Set<String> acceptedOfferIds = existingCollabs
                .where((doc) => (doc.data() as Map<String, dynamic>)['offerId'] != null)
                .map((doc) => (doc.data() as Map<String, dynamic>)['offerId'] as String)
                .toSet();

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final targetShopId = data['shopId'] ?? '';
                final bid = data['bid'] ?? 0;
                final budget = data['budget'] ?? 0;
                final remaining = data['remainingBudget'] ?? budget;
                final targetCategory = data['targetCategory'] ?? 'любая';
                final expires = (data['expires'] as Timestamp?)?.toDate();
                final isOwnOffer = targetShopId == _currentShopId;
                final alreadyAccepted = acceptedOfferIds.contains(doc.id);

                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(
                      isOwnOffer ? 'ВАША ОФЕРТА: Магазин $targetShopId платит $bid ₽/переход' 
                                 : 'Магазин $targetShopId платит $bid ₽/переход',
                      style: isOwnOffer ? const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue) : null,
                    ),
                    subtitle: Text('Остаток: $remaining / $budget ₽ | Категория: $targetCategory | До: ${expires?.toLocal().toString().split(' ')[0] ?? 'не ограничено'}'),
                    trailing: isOwnOffer
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.orange),
                                onPressed: () => _editOffer(doc.id, data),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteOffer(doc.id),
                              ),
                            ],
                          )
                        : alreadyAccepted
                            ? const Chip(label: Text('Уже источник'), backgroundColor: Colors.grey)
                            : ElevatedButton.icon(
                                icon: const Icon(Icons.trending_up),
                                label: const Text('Стать источником'),
                                onPressed: () => _acceptOffer(doc.id, targetShopId, bid),
                              ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ==================== ДИАЛОГ СОЗДАНИЯ ОФЕРТЫ ====================
  Future<void> _showCreateOfferDialog() async {
    final bidCtrl = TextEditingController();
    final budgetCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    DateTime expires = DateTime.now().add(const Duration(days: 30));

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Создать аукционную оферту (вы платите за трафик)'),
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
                  decoration: const InputDecoration(labelText: 'Категория источника (оставьте пустым – любой)'),
                ),
                const SizedBox(height: 8),
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
                    if (picked != null) setStateDialog(() => expires = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final bid = int.tryParse(bidCtrl.text);
                final budget = int.tryParse(budgetCtrl.text);
                if (bid == null || budget == null || bid <= 0 || budget <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ставка и бюджет должны быть положительными числами')));
                  return;
                }
                final data = {
                  'shopId': _currentShopId,
                  'bid': bid,
                  'budget': budget,
                  'remainingBudget': budget,
                  'targetCategory': categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim(),
                  'status': 'active',
                  'expires': Timestamp.fromDate(expires),
                  'createdAt': FieldValue.serverTimestamp(),
                };
                final docRef = await _firestore.collection('auction_offers').add(data);
                // 🆕 Аудит создания оферты
                AuditLogger.log(
                  action: 'create',
                  collection: 'auction_offers',
                  docId: docRef.id,
                  changes: data,
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оферта создана, теперь другие магазины могут откликнуться')));
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== РЕДАКТИРОВАНИЕ ОФЕРТЫ ====================
  Future<void> _editOffer(String offerId, Map<String, dynamic> current) async {
    final bidCtrl = TextEditingController(text: current['bid'].toString());
    final budgetCtrl = TextEditingController(text: current['budget'].toString());
    final categoryCtrl = TextEditingController(text: current['targetCategory'] ?? '');
    DateTime expires = (current['expires'] as Timestamp).toDate();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Редактировать оферту'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: bidCtrl, decoration: const InputDecoration(labelText: 'Ставка (руб./переход)'), keyboardType: TextInputType.number),
                TextField(controller: budgetCtrl, decoration: const InputDecoration(labelText: 'Общий бюджет (руб.)'), keyboardType: TextInputType.number),
                TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Категория источника (оставьте пустым – любой)')),
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
                    if (picked != null) setStateDialog(() => expires = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final bid = int.tryParse(bidCtrl.text);
                final budget = int.tryParse(budgetCtrl.text);
                if (bid == null || budget == null || bid <= 0 || budget <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ставка и бюджет должны быть положительными числами')));
                  return;
                }
                final data = {
                  'bid': bid,
                  'budget': budget,
                  'remainingBudget': budget,
                  'targetCategory': categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim(),
                  'expires': Timestamp.fromDate(expires),
                };
                await _firestore.collection('auction_offers').doc(offerId).update(data);
                // 🆕 Аудит редактирования оферты
                AuditLogger.log(
                  action: 'update',
                  collection: 'auction_offers',
                  docId: offerId,
                  changes: data,
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оферта обновлена')));
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== УДАЛЕНИЕ ОФЕРТЫ ====================
  Future<void> _deleteOffer(String offerId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить оферту?'),
        content: const Text('Это действие нельзя отменить. Все связанные коллаборации останутся активными, но новые отклики будут невозможны.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('auction_offers').doc(offerId).delete();
      // 🆕 Аудит удаления оферты
      AuditLogger.log(
        action: 'delete',
        collection: 'auction_offers',
        docId: offerId,
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оферта удалена')));
    }
  }

  // ==================== ОТКЛИК НА ОФЕРТУ (СТАТЬ ИСТОЧНИКОМ) ====================
  Future<void> _acceptOffer(String offerId, String targetShopId, int bid) async {
    // Проверка категории текущего магазина
    final currentShopDoc = await _firestore.collection('shops').doc(_currentShopId).get();
    if (!currentShopDoc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка: ваш магазин не найден')));
      return;
    }
    final currentCategory = currentShopDoc.data()?['category'] as String?;
    final offerDoc = await _firestore.collection('auction_offers').doc(offerId).get();
    if (!offerDoc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оферта уже не существует')));
      return;
    }
    final offerData = offerDoc.data()!;
    final requiredCategory = offerData['targetCategory'] as String?;
    if (requiredCategory != null && requiredCategory.isNotEmpty && currentCategory != requiredCategory) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ваш магазин не подходит: требуется категория "$requiredCategory", а у вас "$currentCategory"'),
      ));
      return;
    }

    // Проверка, не принимал ли этот магазин уже эту оферту
    final existingCollab = await _firestore.collection('active_collabs')
        .where('fromShopId', isEqualTo: _currentShopId)
        .where('offerId', isEqualTo: offerId)
        .limit(1)
        .get();
    if (existingCollab.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы уже являетесь источником по этой оферте')));
      return;
    }

    // Подтверждение
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Стать источником трафика?'),
        content: Text('Вы соглашаетесь направлять посетителей в магазин $targetShopId. За каждого перешедшего вы получите $bid руб. (деньги платит целевой магазин).\n\nАктивная коллаборация будет создана автоматически. После вашего отклика оферта станет недоступной для других магазинов.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да, создать')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // Создаём активную коллаборацию
      final collabData = {
        'fromShopId': _currentShopId,
        'toShopId': targetShopId,
        'expires': Timestamp.fromDate(DateTime.now().add(const Duration(days: 90))),
        'clicks': 0,
        'bid': bid,
        'type': 'auction_response',
        'offerId': offerId,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final collabDocRef = await _firestore.collection('active_collabs').add(collabData);
      // 🆕 Аудит создания коллаборации
      AuditLogger.log(
        action: 'create',
        collection: 'active_collabs',
        docId: collabDocRef.id,
        changes: collabData,
      );

      // Деактивируем оферту, чтобы её больше никто не мог принять
      final offerUpdate = {
        'status': 'taken',
        'takenBy': _currentShopId,
        'takenAt': FieldValue.serverTimestamp(),
      };
      await _firestore.collection('auction_offers').doc(offerId).update(offerUpdate);
      // 🆕 Аудит изменения статуса оферты
      AuditLogger.log(
        action: 'update',
        collection: 'auction_offers',
        docId: offerId,
        changes: offerUpdate,
      );

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Коллаборация создана! Оферта больше не доступна для других магазинов.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }
}