import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuditLogger {
  /// Записывает событие в коллекцию `admin_logs`.
  /// [action] – 'create', 'update', 'delete'.
  /// [collection] – название коллекции Firestore, в которой произошло изменение.
  /// [docId] – идентификатор изменённого/удалённого документа.
  /// [changes] – карта изменённых полей (для update) или весь объект (для create).
  static Future<void> log({
    required String action,
    required String collection,
    required String docId,
    Map<String, dynamic>? changes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'unknown';
    await FirebaseFirestore.instance.collection('admin_logs').add({
      'timestamp': FieldValue.serverTimestamp(),
      'adminEmail': email,
      'action': action,
      'collection': collection,
      'docId': docId,
      'changes': changes ?? {},
    });
  }
}