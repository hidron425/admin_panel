import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

class MallProfileScreen extends StatefulWidget {
  final String? mallId;
  const MallProfileScreen({super.key, this.mallId});

  @override
  State<MallProfileScreen> createState() => _MallProfileScreenState();
}

class _MallProfileScreenState extends State<MallProfileScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  final _nameController = TextEditingController();
  final _mapImageUrlController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMallData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mapImageUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadMallData() async {
    if (widget.mallId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data = await _sb
          .from('malls')
          .select()
          .eq('firestore_id', widget.mallId!)
          .maybeSingle();
      if (data != null) {
        _nameController.text = data['name'] ?? widget.mallId!;
        _mapImageUrlController.text = data['map_image_url'] ?? '';
      } else {
        _nameController.text = widget.mallId!;
      }
    } catch (e) {
      debugPrint('❌ _loadMallData: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveMallProfile() async {
    final data = <String, dynamic>{
      'firestore_id': widget.mallId,
      'name': _nameController.text.trim(),
      'map_image_url': _mapImageUrlController.text.trim(),
    };
    try {
      await _sb.from('malls').upsert(data, onConflict: 'firestore_id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль ТЦ сохранён')),
        );
      }
    } catch (e) {
      debugPrint('❌ _saveMallProfile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль ТЦ')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Название ТЦ'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _mapImageUrlController,
                    decoration: const InputDecoration(labelText: 'URL карты ТЦ'),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saveMallProfile,
                    child: const Text('Сохранить'),
                  ),
                ],
              ),
            ),
    );
  }
}