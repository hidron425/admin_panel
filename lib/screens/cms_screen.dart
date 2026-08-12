import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:admin_panel/utils/audit.dart';

class CmsScreen extends StatefulWidget {
  const CmsScreen({super.key});

  @override
  State<CmsScreen> createState() => _CmsScreenState();
}

class _CmsScreenState extends State<CmsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _keyController = TextEditingController();
  final _textController = TextEditingController();
  String? _editingDocId;

  // Предопределённые ключи для удобства
  final List<String> _commonKeys = [
    'home_welcome',
    'quest_rules',
    'faq',
    'about',
  ];

  @override
  void dispose() {
    _keyController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadContent(String key) async {
    final snap = await _firestore.collection('content').where('key', isEqualTo: key).limit(1).get();
    if (snap.docs.isNotEmpty) {
      final doc = snap.docs.first;
      _editingDocId = doc.id;
      _keyController.text = key;
      _textController.text = doc.data()['text'] ?? '';
    } else {
      _editingDocId = null;
      _keyController.text = key;
      _textController.clear();
    }
    setState(() {});
  }

  Future<void> _saveContent() async {
    final key = _keyController.text.trim();
    final text = _textController.text.trim();
    if (key.isEmpty) return;

    final data = {
      'key': key,
      'text': text,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (_editingDocId != null) {
      await _firestore.collection('content').doc(_editingDocId).update(data);
      AuditLogger.log(action: 'update', collection: 'content', docId: _editingDocId!, changes: data);
    } else {
      final ref = await _firestore.collection('content').add(data);
      _editingDocId = ref.id;
      AuditLogger.log(action: 'create', collection: 'content', docId: ref.id, changes: data);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление контентом'),
      ),
      body: Row(
        children: [
          // Список ключей
          SizedBox(
            width: 220,
            child: ListView(
              children: _commonKeys.map((key) {
                return ListTile(
                  title: Text(key),
                  onTap: () => _loadContent(key),
                );
              }).toList(),
            ),
          ),
          const VerticalDivider(width: 1),
          // Редактор
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _keyController,
                    decoration: const InputDecoration(labelText: 'Ключ (уникальный идентификатор)'),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        labelText: 'Текст',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _saveContent,
                    icon: const Icon(Icons.save),
                    label: const Text('Сохранить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}