import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'store_screen.dart';
import 'stats_screen.dart';
import 'promotions_screen.dart';
import 'collabs_screen.dart';
import 'banners_screen.dart';   // 🆕 импорт экрана баннеров
import 'analytics_screen.dart';
import 'mall_map_editor_screen.dart';

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
      const BannersScreen(),   // 🆕 новый экран
    ];
  }

  void setPage(int index) {
    if (mounted) {
      setState(() {
        _selectedIndex = index;
      });
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление магазином'),
        actions: [
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
              child: const Text('Меню', style: TextStyle(color: Colors.white, fontSize: 24)),
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
              leading: const Icon(Icons.campaign),          // 🆕 иконка рупора
              title: const Text('Баннеры'),
              selected: _selectedIndex == 4,               // 🆕 новый индекс
              onTap: () => setPage(4),
            ),
          ListTile(
  leading: const Icon(Icons.analytics_outlined),
  title: const Text('Общая аналитика'),
  onTap: () {
    Navigator.pop(context);               // закрываем Drawer
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
    );
  },
),
ListTile(
  leading: const Icon(Icons.map),
  title: const Text('Управление картой'),
  onTap: () {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MallMapEditorScreen()));
  },
),
          ],
        ),
      ),
      body: _pages[_selectedIndex],
    );
  }
}