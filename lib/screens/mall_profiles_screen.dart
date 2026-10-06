import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:admin_panel/utils/app_state.dart';
import 'mall_profile_screen.dart';

class MallProfilesScreen extends StatefulWidget {
  const MallProfilesScreen({super.key});

  @override
  State<MallProfilesScreen> createState() => _MallProfilesScreenState();
}

class _MallProfilesScreenState extends State<MallProfilesScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  List<Map<String, dynamic>> _malls = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMalls();
  }

  Future<void> _loadMalls() async {
    setState(() => _loading = true);
    try {
      final data = await _sb.from('malls').select().order('name');
      if (mounted) {
        setState(() {
          _malls = (data as List).map((j) => Map<String, dynamic>.from(j)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadMalls: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

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
              try {
                await _sb.from('malls').upsert({
                  'firestore_id': id,
                  'name': name,
                  'map_image_url': '',
                  'image_width': 2045,
                  'image_height': 731,
                }, onConflict: 'firestore_id');
                if (mounted) Navigator.pop(ctx);
                _loadMalls();
              } catch (e) {
                debugPrint('❌ create mall: $e');
              }
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _malls.isEmpty
              ? const Center(child: Text('Нет ТЦ'))
              : ListView.builder(
                  itemCount: _malls.length,
                  itemBuilder: (context, index) {
                    final data = _malls[index];
                    final mallId = data['firestore_id'] as String? ?? '';
                    final mallName = data['name'] as String? ?? mallId;
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
                            ).then((_) => _loadMalls());
                          },
                        );
                      },
                    );
                  },
                ),
    );
  }
}