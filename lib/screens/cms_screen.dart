import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:admin_panel/utils/audit.dart';
import 'package:admin_panel/utils/app_state.dart';

class CmsScreen extends StatefulWidget {
  const CmsScreen({super.key});

  @override
  State<CmsScreen> createState() => _CmsScreenState();
}

class _CmsScreenState extends State<CmsScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  final _keyController = TextEditingController();
  final _textController = TextEditingController();
  String? _editingDocId;
  String? _selectedMallId;

  final List<String> _commonKeys = [
    'home_welcome',
    'quest_rules',
    'faq',
    'about',
  ];

  @override
  void initState() {
    super.initState();
    _selectedMallId = AppState.selectedMallId.value;
    AppState.selectedMallId.addListener(_onMallChanged);
  }

  @override
  void dispose() {
    AppState.selectedMallId.removeListener(_onMallChanged);
    _keyController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onMallChanged() {
    if (_selectedMallId != AppState.selectedMallId.value) {
      setState(() {
        _selectedMallId = AppState.selectedMallId.value;
        _editingDocId = null;
        _textController.clear();
      });
    }
  }

  Future<void> _loadContent(String key) async {
    try {
      dynamic query = _sb.from('content').select().eq('key', key);

      if (_selectedMallId != null) {
        query = query.eq('mall_id', _selectedMallId!);
      } else {
        query = query.isFilter('mall_id', null);
      }

      final data = await query.limit(1).maybeSingle();

      if (data != null) {
        _editingDocId = data['id'].toString();
        _keyController.text = key;
        _textController.text = (data['text'] as String?) ?? '';
      } else {
        _editingDocId = null;
        _keyController.text = key;
        _textController.clear();
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ _loadContent: $e');
      if (mounted) {
        setState(() {
          _editingDocId = null;
          _keyController.text = key;
          _textController.clear();
        });
      }
    }
  }

  Future<void> _saveContent() async {
    final key = _keyController.text.trim();
    final text = _textController.text.trim();
    if (key.isEmpty) return;

    final data = <String, dynamic>{
      'key': key,
      'text': text,
      'mall_id': _selectedMallId,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      if (_editingDocId != null) {
        await _sb.from('content').update(data).eq('id', _editingDocId!);
        AuditLogger.log(
          action: 'update',
          collection: 'content',
          docId: _editingDocId!,
          changes: data,
        );
      } else {
        final result = await _sb
            .from('content')
            .insert(data)
            .select('id')
            .single();
        _editingDocId = result['id'].toString();
        AuditLogger.log(
          action: 'create',
          collection: 'content',
          docId: _editingDocId!,
          changes: data,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сохранено')),
        );
      }
    } catch (e) {
      debugPrint('❌ _saveContent: $e');
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
      appBar: AppBar(
        title: Text(_selectedMallId == null
            ? 'Управление контентом (Все ТЦ)'
            : 'Управление контентом (${_selectedMallId})'),
      ),
      body: Row(
        children: [
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