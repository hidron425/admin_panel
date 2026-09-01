import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

class DebugLogsScreen extends StatelessWidget {
  const DebugLogsScreen({super.key});

  String _formatLog(Map<String, dynamic> data) {
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final dateStr = timestamp != null
        ? DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp)
        : '—';
    final currentShop = data['currentShopName'] ?? data['currentShopId'] ?? '—';
    final candidateShops = (data['candidateShops'] as List<dynamic>? ?? [])
        .map((e) => e is Map<String, dynamic>
            ? '${e['name']} (id=${e['shopId']}, priority=${e['priority']}, fav=${e['isFavorite']})'
            : e.toString())
        .join('; ');
    final selectedShops = (data['selectedShops'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .join(', ');
    final collabShop = data['collabShopName'] ?? '';
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
    final snapshot = await FirebaseFirestore.instance
        .collection('debug_fork_logs')
        .orderBy('timestamp', descending: false)
        .get();

    final buffer = StringBuffer();
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      buffer.write(_formatLog(data));
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
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
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('debug_fork_logs')
            .orderBy('timestamp', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Логов пока нет'));
          }

          final allText = docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _formatLog(data);
          }).join('\n');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(allText),
          );
        },
      ),
    );
  }
}