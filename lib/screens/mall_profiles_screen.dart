import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:admin_panel/utils/app_state.dart';
import 'mall_profile_screen.dart';   // <-- важно: импорт класса MallProfileScreen

class MallProfilesScreen extends StatefulWidget {
  const MallProfilesScreen({super.key});
  @override
  State<MallProfilesScreen> createState() => _MallProfilesScreenState();
}

class _MallProfilesScreenState extends State<MallProfilesScreen> {
  final _firestore = FirebaseFirestore.instance;

  Future<void> _createMall() async {
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
              await _firestore.collection('malls').doc(id).set({
                'name': name,
                'id': id,
                'mapImageUrl': '',
                'imageWidth': 2045,
                'imageHeight': 731,
              });
              Navigator.pop(ctx);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профили ТЦ')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createMall,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('malls').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final malls = snapshot.data!.docs;
          if (malls.isEmpty) return const Center(child: Text('Нет ТЦ'));

          return ListView.builder(
            itemCount: malls.length,
            itemBuilder: (context, index) {
              final data = malls[index].data() as Map<String, dynamic>;
              final mallId = malls[index].id;
              final mallName = data['name'] ?? mallId;
              return ValueListenableBuilder<String?>(
                valueListenable: AppState.selectedMallId,
                builder: (context, selectedMallId, _) {
                  final isSelected = selectedMallId == mallId;
                  return ListTile(
                    title: Text(mallName),
                    subtitle: Text(mallId),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.radio_button_unchecked),
                    onTap: () {
                      AppState.selectedMallId.value = mallId;
                      AppState.selectedMallName.value = mallName;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MallProfileScreen(mallId: mallId),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}