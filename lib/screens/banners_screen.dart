import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BannersScreen extends StatefulWidget {
  const BannersScreen({Key? key}) : super(key: key);

  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

class _BannersScreenState extends State<BannersScreen> {
  final _firestore = FirebaseFirestore.instance;

  Future<void> _addBanner() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final discountCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить баннер'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок')),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание')),
              TextField(controller: colorCtrl, decoration: const InputDecoration(labelText: 'Цвет (#RRGGBB)')),
              TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'ID магазина-цели')),
              TextField(controller: discountCtrl, decoration: const InputDecoration(labelText: 'Скидка (например -20%)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              await _firestore.collection('banners').add({
                'title': titleCtrl.text.trim(),
                'description': descCtrl.text.trim(),
                'color': colorCtrl.text.trim(),
                'targetShopId': targetCtrl.text.trim(),
                'discount': discountCtrl.text.trim(),
              });
              Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  Future<void> _editBanner(String id, Map<String, dynamic> data) async {
    final titleCtrl = TextEditingController(text: data['title']);
    final descCtrl = TextEditingController(text: data['description']);
    final colorCtrl = TextEditingController(text: data['color']);
    final targetCtrl = TextEditingController(text: data['targetShopId']);
    final discountCtrl = TextEditingController(text: data['discount']);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать баннер'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок')),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание')),
              TextField(controller: colorCtrl, decoration: const InputDecoration(labelText: 'Цвет (#RRGGBB)')),
              TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'ID магазина-цели')),
              TextField(controller: discountCtrl, decoration: const InputDecoration(labelText: 'Скидка')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              await _firestore.collection('banners').doc(id).update({
                'title': titleCtrl.text.trim(),
                'description': descCtrl.text.trim(),
                'color': colorCtrl.text.trim(),
                'targetShopId': targetCtrl.text.trim(),
                'discount': discountCtrl.text.trim(),
              });
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBanner(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить баннер?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('banners').doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Управление баннерами')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('banners').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final banners = snapshot.data!.docs;
          if (banners.isEmpty) {
            return const Center(child: Text('Нет баннеров'));
          }
          return ListView.builder(
            itemCount: banners.length,
            itemBuilder: (context, index) {
              final doc = banners[index];
              final data = doc.data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(data['title'] ?? 'Без названия'),
                  subtitle: Text(data['description'] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editBanner(doc.id, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteBanner(doc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBanner,
        child: const Icon(Icons.add),
      ),
    );
  }
}