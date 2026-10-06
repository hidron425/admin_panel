import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({super.key});

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    try {
      final data = await _sb
          .from('debug_fork_logs')
          .select()
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _logs = (data as List).map((j) => Map<String, dynamic>.from(j)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadLogs: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatLog(Map<String, dynamic> data) {
    final tsRaw = data['created_at'] as String?;
    final ts = tsRaw != null ? DateTime.tryParse(tsRaw) : null;
    final dateStr = ts != null ? DateFormat('yyyy-MM-dd HH:mm:ss').format(ts) : '—';
    final currentShop = data['current_shop_name'] ?? data['current_shop_id'] ?? '—';

    final candidateShops = (data['candidate_shops'] as List<dynamic>? ?? [])
        .map((e) => e is Map
            ? '${e['name']} (id=${e['shop_id']}, priority=${e['priority']}, fav=${e['is_favorite']})'
            : e.toString())
        .join('; ');

    final selectedShops = (data['selected_shops'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .join(', ');

    final collabShop = data['collab_shop_name'] ?? '';

    return '''
Время: $dateStr
Текущий магазин: $currentShop
Кандидаты: $candidateShops
Коллаборация: ${collabShop.isEmpty ? 'нет' : collabShop}
Выбрано: $selectedShops
-------------------------------
''';
  }

  Future<void> _copyAllLogs() async {
    final buffer = StringBuffer();
    for (final log in _logs) {
      buffer.write(_formatLog(log));
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Логи скопированы')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Логи подбора (отладка)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Скопировать все логи',
            onPressed: _copyAllLogs,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text('Логов пока нет'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_logs.map(_formatLog).join('\n')),
                ),
    );
  }
}