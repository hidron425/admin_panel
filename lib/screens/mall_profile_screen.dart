import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MallProfileScreen extends StatefulWidget {
  final String? mallId;
  const MallProfileScreen({super.key, this.mallId});

  @override
  State<MallProfileScreen> createState() => _MallProfileScreenState();
}

class _MallProfileScreenState extends State<MallProfileScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _nameController = TextEditingController();
  final _mapImageUrlController = TextEditingController();
  bool _loading = true;
  String? _docId;

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
    if (widget.mallId == null) return;
    final snap = await _firestore
        .collection('malls')
        .where('id', isEqualTo: widget.mallId)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      final doc = snap.docs.first;
      _docId = doc.id;
      final data = doc.data() as Map<String, dynamic>;
      _nameController.text = data['name'] ?? widget.mallId!;
      _mapImageUrlController.text = data['mapImageUrl'] ?? '';
    } else {
      _nameController.text = widget.mallId!;
    }
    setState(() => _loading = false);
  }

  Future<void> _saveMallProfile() async {
    final data = {
      'name': _nameController.text.trim(),
      'mapImageUrl': _mapImageUrlController.text.trim(),
    };
    if (_docId != null) {
      await _firestore.collection('malls').doc(_docId).update(data);
    } else {
      final ref = await _firestore.collection('malls').add({
        ...data,
        'id': widget.mallId,
      });
      _docId = ref.id;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль ТЦ сохранён')),
      );
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