import 'package:supabase_flutter/supabase_flutter.dart' as supa;

class AuditLogger {
  /// Записывает событие в таблицу `admin_logs`.
  /// [action] – 'create', 'update', 'delete'.
  /// [collection] – название коллекции/таблицы (для совместимости с Firebase-кодом).
  /// [docId] – идентификатор изменённого/удалённого документа.
  /// [changes] – карта изменённых полей (для update) или весь объект (для create).
  static Future<void> log({
    required String action,
    required String collection,
    required String docId,
    Map<String, dynamic>? changes,
  }) async {
    try {
      final user = supa.Supabase.instance.client.auth.currentUser;
      final email = user?.email ?? 'unknown';

      await supa.Supabase.instance.client.from('admin_logs').insert({
        'admin_email': email,
        'action': action,
        'collection': collection,
        'doc_id': docId,
        'changes': changes ?? {},
      });
    } catch (e) {
      // Логирование не должно ломать основной поток
      print('❌ AuditLogger.log: $e');
    }
  }
}