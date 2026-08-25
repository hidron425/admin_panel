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

class AdminScreen extends StatefulWidget {
  final User user;
  const AdminScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedIndex = 0;
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
    _ensureMallsExist();
  }

  Future<void> _ensureMallsExist() async {
    final mallsSnap = await FirebaseFirestore.instance.collection('malls').get();
    if (mallsSnap.docs.isEmpty) {
      // Если коллекция пуста, создаём ТЦ на основе уникальных mallId из shops
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
          'name': mallId, // позже можно изменить
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
              // Обновляем глобальное состояние, чтобы выпадающий список перерисовался
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  void setPage(int index) {
    if (mounted) {
      setState(() => _selectedIndex = index);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-панель'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                widget.user.email ?? '',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
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
                    return DropdownButton<String?>(
                      value: mallId,
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
                            : (malls.firstWhere((d) => d.id == val).data()
                                    as Map<String, dynamic>)['name'];
                        setState(() {});
                      },
                    );
                  },
                );
              },
            ),
          ),
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
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Меню',
                    style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
                  Text(
                    widget.user.email ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.store),
              title: const Text('Мой магазин'),
              selected: _selectedIndex == 0,
              onTap: () => setPage(0),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Статистика'),
              selected: _selectedIndex == 1,
              onTap: () => setPage(1),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('Акции (календарь)'),
              selected: _selectedIndex == 2,
              onTap: () => setPage(2),
            ),
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
            // Убрали "Профили ТЦ"
          ],
        ),
      ),
      body: _pages[_selectedIndex],
    );
  }
}