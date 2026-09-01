import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'store_screen.dart';
import 'stats_screen.dart';
import 'promotions_screen.dart';
import 'collabs_screen.dart';
import 'banners_screen.dart';
import 'all_stores_screen.dart';
import 'bonus_rules_screen.dart';
import 'user_management_screen.dart';
import 'mall_map_editor_screen.dart';
import 'cms_screen.dart';
import 'daily_tasks_manager_screen.dart';
import 'analytics_screen.dart';
import 'extended_analytics_screen.dart';
import 'package:admin_panel/utils/app_state.dart';
import 'debug_logs_screen.dart';

class AdminScreen extends StatefulWidget {
  final User user;
  const AdminScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _isAggregator = false;
  bool _roleLoaded = false;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      StoreScreen(onTabSelected: setPage),
      const StatsScreen(),
      const PromotionsScreen(),
      const CollabsScreen(),
      const BannersScreen(),
      const AllStoresScreen(),
      const BonusRulesScreen(),
      const UserManagementScreen(),
      const MallMapEditorScreen(),
      const CmsScreen(),
      const DailyTasksManagerScreen(),
      const AnalyticsScreen(),
      const ExtendedAnalyticsScreen(),
    ];
    _loadUserRole();
    _ensureMallsExist();
  }

  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.email!)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final isAggregator = data['storeId'] == null || data['role'] == 'admin';
        if (mounted) {
          setState(() {
            _isAggregator = isAggregator;
            _selectedIndex = isAggregator ? -1 : 0;
            _roleLoaded = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isAggregator = true;
            _selectedIndex = -1;
            _roleLoaded = true;
          });
        }
      }
    } else {
      if (mounted) setState(() => _roleLoaded = true);
    }
  }

  Future<void> _ensureMallsExist() async {
    final mallsSnap = await FirebaseFirestore.instance.collection('malls').get();
    if (mallsSnap.docs.isEmpty) {
      final shopsSnap = await FirebaseFirestore.instance.collection('shops').get();
      final mallIds = shopsSnap.docs
          .map((doc) => (doc.data()['mallId'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final batch = FirebaseFirestore.instance.batch();
      for (final mallId in mallIds) {
        final ref = FirebaseFirestore.instance.collection('malls').doc(mallId);
        batch.set(ref, {
          'id': mallId,
          'name': mallId,
          'mapImageUrl': '',
          'imageWidth': 2045,
          'imageHeight': 731,
        });
      }
      await batch.commit();
    }
  }

  Future<void> _showCreateMallDialog() async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый ТЦ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Название')),
            TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'ID (например mall_mega)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              final id = idCtrl.text.trim();
              final name = nameCtrl.text.trim();
              if (id.isEmpty || name.isEmpty) return;
              await FirebaseFirestore.instance.collection('malls').doc(id).set({
                'name': name,
                'id': id,
                'mapImageUrl': '',
                'imageWidth': 2045,
                'imageHeight': 731,
              });
              if (mounted) setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  // ---------- Временные методы для массовой генерации тестовых данных ----------
  String _transliterate(String input) {
    const Map<String, String> cyrillic = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd',
      'е': 'e', 'ё': 'e', 'ж': 'zh', 'з': 'z', 'и': 'i',
      'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
      'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't',
      'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch',
      'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '',
      'э': 'e', 'ю': 'yu', 'я': 'ya',
      'А': 'a', 'Б': 'b', 'В': 'v', 'Г': 'g', 'Д': 'd',
      'Е': 'e', 'Ё': 'e', 'Ж': 'zh', 'З': 'z', 'И': 'i',
      'Й': 'y', 'К': 'k', 'Л': 'l', 'М': 'm', 'Н': 'n',
      'О': 'o', 'П': 'p', 'Р': 'r', 'С': 's', 'Т': 't',
      'У': 'u', 'Ф': 'f', 'Х': 'kh', 'Ц': 'ts', 'Ч': 'ch',
      'Ш': 'sh', 'Щ': 'sch', 'Ъ': '', 'Ы': 'y', 'Ь': '',
      'Э': 'e', 'Ю': 'yu', 'Я': 'ya',
    };
    final sb = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (cyrillic.containsKey(char)) {
        sb.write(cyrillic[char]);
      } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
        sb.write(char);
      } else {
        sb.write('_');
      }
    }
    return sb.toString().toLowerCase();
  }

  Future<void> _generateTestShops() async {
    const String mallId = 'mall_afimall';

    // Списки брендов (30 в каждой категории)
    const List<String> cafeBrands = [
      'Starbucks', 'Costa Coffee', 'Cofix', 'Шоколадница', 'Даблби',
      'Surf Coffee', 'One Price Coffee', 'Coffee Like', 'Baggins Coffee', 'Правда Кофе',
      'Tim Hortons', 'Dunkin Donuts', 'McCafé', 'Krispy Kreme', 'KFC Coffee',
      'Burger King Café', 'Subway Coffee', 'Tea Funny', 'Чайникофф', 'Урюк',
      'Varvar Cafe', 'Cezve Coffee', 'Bloom-n-Brew', 'Sigmund Freud', 'Espresso House',
      'Coffee Bean', 'Caribou Coffee', 'Gloria Jean\'s Coffees', 'Illy Caffè', 'Lavazza Espression'
    ];

    const List<String> clothingBrands = [
      'Zara', 'H&M', 'Uniqlo', 'Bershka', 'Pull&Bear',
      'Stradivarius', 'Massimo Dutti', 'Oysho', 'Reserved', 'Sinsay',
      'LC Waikiki', 'Adidas', 'Nike', 'Reebok', 'Puma',
      'New Balance', 'Levi\'s', 'Calvin Klein', 'Tommy Hilfiger', 'Lacoste',
      'Ralph Lauren', 'Guess', 'United Colors of Benetton', 'Monki', 'Weekday',
      '& Other Stories', 'Arket', 'COS', 'Mango', 'Lime'
    ];

    const List<String> electronicsBrands = [
      'DNS', 'М.Видео', 'Эльдорадо', 'Ситилинк', 're:Store',
      'Samsung', 'Xiaomi', 'Honor', 'Huawei', 'Sony Centre',
      'Bosch', 'Philips', 'Dyson', 'Kitfort', 'Redmond',
      'Polaris', 'Bork', 'DeLonghi', 'Electrolux', 'Miele',
      'LG', 'Haier', 'Tefal', 'Braun', 'Gorenje',
      'Apple (iPort)', 'Ноутбук.ру', 'Технопарк', 'Онлайн-трейд', 'Юлмарт'
    ];

    const Map<String, String> categoryIcons = {
      'cafe': '☕',
      'clothing': '👗',
      'electronics': '🔌',
    };

    const Map<String, List<String>> discountsByCategory = {
      'cafe': ['-20% на второй кофе', 'Скидка 15% на десерты', 'Комбо-наборы со скидкой 10%', 'Счастливые часы: -25%', 'Бонусная карта: 5% кэшбэк'],
      'clothing': ['-30% на новую коллекцию', 'Скидки до -50%', 'Акция 1+1=3', 'Скидка 20% по промокоду', 'Финальные распродажи -70%'],
      'electronics': ['Скидка 10% на аксессуары', 'Trade-in: скидка до 25%', 'Рассрочка 0-0-24', 'Подарок при покупке', 'Программа лояльности -5%'],
    };

    // 1. Удаляем все магазины этого ТЦ
    final existingShops = await FirebaseFirestore.instance
        .collection('shops')
        .where('mallId', isEqualTo: mallId)
        .get();

    final deleteBatch = FirebaseFirestore.instance.batch();
    for (final doc in existingShops.docs) {
      deleteBatch.delete(doc.reference);
    }
    await deleteBatch.commit();

    // 2. Создаём магазины и пользователей
    final createBatch = FirebaseFirestore.instance.batch();
    int shopCount = 0;
    final List<Map<String, String>> usersToCreate = [];

    for (final category in ['cafe', 'clothing', 'electronics']) {
      final List<String> brands = category == 'cafe'
          ? cafeBrands
          : category == 'clothing'
              ? clothingBrands
              : electronicsBrands;

      for (int i = 0; i < brands.length; i++) {
        final name = brands[i];
        final discountIndex = i % discountsByCategory[category]!.length;
        final slug = name.replaceAll(' ', '_');
        final transliterated = _transliterate(slug);
        final email = '$transliterated@example.com';

        final shop = {
          'name': name,
          'icon': categoryIcons[category],
          'category': category,
          'discount': discountsByCategory[category]![discountIndex],
          'shortDiscount': discountsByCategory[category]![discountIndex],
          'description': '$name — магазин категории $category.',
          'location': 'ТЦ Афимолл, этаж ${(i % 3) + 1}',
          'mallId': mallId,
          'priority': (i % 5) + 1,
          'imageUrl': '',
          'infoImageUrl': '',
          'mapX': 0.05 + (i * 0.03) % 0.9,
          'mapY': 0.05 + ((i * 7) % 10) * 0.08,
          'mapWidth': 0.04,
          'mapHeight': 0.06,
          'imageTransform': null,
          'infoImageTransform': null,
          'createdAt': FieldValue.serverTimestamp(),
        };

        createBatch.set(FirebaseFirestore.instance.collection('shops').doc(slug), shop);
        usersToCreate.add({
          'email': email,
          'password': 'test123',
          'storeId': slug,
        });
        shopCount++;
      }
    }

    await createBatch.commit();

    // 3. Создаём пользователей в Firebase Auth и Firestore users
    int userCount = 0;
    for (final userInfo in usersToCreate) {
      try {
        final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(userInfo['email']!);
        if (methods.isEmpty) {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: userInfo['email']!,
            password: userInfo['password']!,
          );
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userInfo['email'])
            .set({
          'storeId': userInfo['storeId'],
          'email': userInfo['email'],
          'role': 'shop',
        });
        userCount++;
      } catch (e) {
        print('Ошибка для ${userInfo['email']}: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Магазинов: $shopCount, профилей создано: $userCount')),
      );
    }
  }

  void setPage(int index) {
    if (!mounted) return;
    setState(() => _selectedIndex = index);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  Widget _buildAggregatorDashboard() {
    final items = <Map<String, dynamic>>[
      {'icon': Icons.bar_chart, 'title': 'Статистика', 'index': 1},
      {'icon': Icons.calendar_month, 'title': 'Акции', 'index': 2},
      {'icon': Icons.link, 'title': 'Коллаборации', 'index': 3},
      {'icon': Icons.campaign, 'title': 'Баннеры', 'index': 4},
      {'icon': Icons.apartment, 'title': 'Все магазины', 'index': 5},
      {'icon': Icons.card_giftcard, 'title': 'Бонусные правила', 'index': 6},
      {'icon': Icons.people, 'title': 'Пользователи', 'index': 7},
      {'icon': Icons.map, 'title': 'Редактор карты', 'index': 8},
      {'icon': Icons.edit_note, 'title': 'Контент (CMS)', 'index': 9},
      {'icon': Icons.task_alt, 'title': 'Ежедневные задания', 'index': 10},
      {'icon': Icons.analytics, 'title': 'Общая аналитика', 'index': 11},
      {'icon': Icons.insights, 'title': 'Расширенная аналитика', 'index': 12},
    ];

    return GridView.extent(
      padding: const EdgeInsets.all(16),
      maxCrossAxisExtent: 180,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.9,
      children: items.map((item) {
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setPage(item['index'] as int),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item['icon'] as IconData, size: 28, color: Theme.of(context).primaryColor),
                const SizedBox(height: 6),
                Text(
                  item['title'] as String,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.1),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_roleLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDashboard = _isAggregator && _selectedIndex == -1;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Админ-панель'),
        leading: (_isAggregator && _selectedIndex == -1) || (!_isAggregator && _selectedIndex == 0)
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setPage(_isAggregator ? -1 : 0),
              ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(widget.user.email ?? '', style: const TextStyle(fontSize: 14)),
            ),
          ),
          if (_isAggregator)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ValueListenableBuilder<String?>(
                valueListenable: AppState.selectedMallId,
                builder: (context, mallId, _) {
                  return FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance.collection('malls').get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();
                      final malls = snapshot.data!.docs;
                      final safeValue = malls.any((doc) => doc.id == mallId)
                          ? mallId
                          : null;
                      return DropdownButton<String?>(
                        value: safeValue,
                        hint: const Text('Все ТЦ'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Все ТЦ'),
                          ),
                          ...malls.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name = data['name'] ?? doc.id;
                            return DropdownMenuItem<String?>(
                              value: doc.id,
                              child: Text(name),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          AppState.selectedMallId.value = val;
                          AppState.selectedMallName.value = val == null
                              ? null
                              : (malls
                                          .where((d) => d.id == val)
                                          .toList()
                                          .isNotEmpty
                                      ? (malls
                                              .firstWhere((d) => d.id == val)
                                              .data() as Map<String, dynamic>)['name']
                                      : null);
                          setState(() {});
                        },
                      );
                    },
                  );
                },
              ),
            ),
          if (_isAggregator)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Создать ТЦ',
              onPressed: _showCreateMallDialog,
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Меню', style: TextStyle(color: Colors.white, fontSize: 24)),
                  Text(widget.user.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            if (_isAggregator)
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Главная'),
                selected: _selectedIndex == -1,
                onTap: () => setPage(-1),
              ),
            if (!_isAggregator)
              ListTile(
                leading: const Icon(Icons.store),
                title: const Text('Мой магазин'),
                selected: _selectedIndex == 0,
                onTap: () => setPage(0),
              ),
            if (_isAggregator || !_isAggregator) ...[
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('Статистика'),
                selected: _selectedIndex == 1,
                onTap: () => setPage(1),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('Акции'),
                selected: _selectedIndex == 2,
                onTap: () => setPage(2),
              ),
            ],
            if (_isAggregator) ...[
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Коллаборации'),
                selected: _selectedIndex == 3,
                onTap: () => setPage(3),
              ),
              ListTile(
                leading: const Icon(Icons.campaign),
                title: const Text('Баннеры'),
                selected: _selectedIndex == 4,
                onTap: () => setPage(4),
              ),
              ListTile(
                leading: const Icon(Icons.apartment),
                title: const Text('Все магазины'),
                selected: _selectedIndex == 5,
                onTap: () => setPage(5),
              ),
              ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: const Text('Бонусные правила'),
                selected: _selectedIndex == 6,
                onTap: () => setPage(6),
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Пользователи'),
                selected: _selectedIndex == 7,
                onTap: () => setPage(7),
              ),
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Редактор карты'),
                selected: _selectedIndex == 8,
                onTap: () => setPage(8),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Контент (CMS)'),
                selected: _selectedIndex == 9,
                onTap: () => setPage(9),
              ),
              ListTile(
                leading: const Icon(Icons.task_alt),
                title: const Text('Ежедневные задания'),
                selected: _selectedIndex == 10,
                onTap: () => setPage(10),
              ),
              ListTile(
                leading: const Icon(Icons.analytics),
                title: const Text('Общая аналитика'),
                selected: _selectedIndex == 11,
                onTap: () => setPage(11),
              ),
              ListTile(
                leading: const Icon(Icons.insights),
                title: const Text('Расширенная аналитика'),
                selected: _selectedIndex == 12,
                onTap: () => setPage(12),
              ),
            ],
            const Divider(),
            // 🆕 Временная кнопка генерации
            ListTile(
              leading: const Icon(Icons.add_business),
              title: const Text('Сгенерировать тестовые магазины и профили'),
              onTap: () {
                Navigator.pop(context);
                _generateTestShops();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Выйти'),
              onTap: () => FirebaseAuth.instance.signOut(),
            ),
            ListTile(
  leading: const Icon(Icons.bug_report),
  title: const Text('Логи подбора'),
  onTap: () {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DebugLogsScreen()),
    );
  },
),
          ],
        ),
      ),
      body: isDashboard
          ? _buildAggregatorDashboard()
          : _pages[_selectedIndex],
    );
  }
}