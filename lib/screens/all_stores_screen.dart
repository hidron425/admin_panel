import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:admin_panel/utils/audit.dart';   // 🆕 импорт сервиса аудита

class AllStoresScreen extends StatefulWidget {
  const AllStoresScreen({Key? key}) : super(key: key);

  @override
  State<AllStoresScreen> createState() => _AllStoresScreenState();
}

class _AllStoresScreenState extends State<AllStoresScreen> {
  final _firestore = FirebaseFirestore.instance;

  Future<void> _updateStore(String docId, Map<String, dynamic> data) async {
    await _firestore.collection('shops').doc(docId).update(data);
    // 🆕 Логируем изменение магазина
    AuditLogger.log(
      action: 'update',
      collection: 'shops',
      docId: docId,
      changes: data,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Все магазины')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('shops').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final stores = snapshot.data!.docs;
          if (stores.isEmpty) {
            return const Center(child: Text('Нет магазинов'));
          }
          return ListView.builder(
            itemCount: stores.length,
            itemBuilder: (context, index) {
              final doc = stores[index];
              final data = doc.data() as Map<String, dynamic>;
              final storeId = doc.id;
              return Card(
                margin: const EdgeInsets.all(8),
                child: ExpansionTile(
                  title: Text(data['name'] ?? storeId),
                  subtitle: Text('ID: $storeId'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            initialValue: data['name'] ?? '',
                            decoration: const InputDecoration(labelText: 'Название'),
                            onChanged: (value) => _updateStore(storeId, {'name': value}),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: data['icon'] ?? '',
                            decoration: const InputDecoration(labelText: 'Иконка (эмодзи)'),
                            onChanged: (value) => _updateStore(storeId, {'icon': value}),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: data['discount'] ?? '',
                            decoration: const InputDecoration(labelText: 'Скидка'),
                            onChanged: (value) => _updateStore(storeId, {'discount': value}),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: data['description'] ?? '',
                            decoration: const InputDecoration(labelText: 'Описание'),
                            onChanged: (value) => _updateStore(storeId, {'description': value}),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: data['location'] ?? '',
                            decoration: const InputDecoration(labelText: 'Локация'),
                            onChanged: (value) => _updateStore(storeId, {'location': value}),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: data['category'] ?? '',
                            decoration: const InputDecoration(labelText: 'Категория'),
                            onChanged: (value) => _updateStore(storeId, {'category': value}),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: (data['priority'] ?? 1).toString(),
                            decoration: const InputDecoration(labelText: 'Приоритет (1-10)'),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final int? prio = int.tryParse(value);
                              if (prio != null) _updateStore(storeId, {'priority': prio});
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: (data['pushCredits'] ?? 0).toString(),
                            decoration: const InputDecoration(labelText: 'Кредиты пушей'),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final int? credits = int.tryParse(value);
                              if (credits != null) _updateStore(storeId, {'pushCredits': credits});
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: data['subscriptionPlan'] ?? 'start',
                            decoration: const InputDecoration(labelText: 'Тарифный план'),
                            items: const [
                              DropdownMenuItem(value: 'start', child: Text('Start')),
                              DropdownMenuItem(value: 'business', child: Text('Business')),
                              DropdownMenuItem(value: 'premium', child: Text('Premium')),
                              DropdownMenuItem(value: 'corp', child: Text('Corp')),
                            ],
                            onChanged: (value) => _updateStore(storeId, {'subscriptionPlan': value}),
                          ),
                          const SizedBox(height: 12),
                          ListTile(
                            title: const Text('Подписка истекает'),
                            subtitle: Text(
                              data['subscriptionExpiry'] != null
                                  ? (data['subscriptionExpiry'] as Timestamp).toDate().toLocal().toString().split(' ')[0]
                                  : 'Не установлена',
                            ),
                            trailing: const Icon(Icons.calendar_today),
                            onTap: () async {
                              DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: data['subscriptionExpiry'] != null
                                    ? (data['subscriptionExpiry'] as Timestamp).toDate()
                                    : DateTime.now().add(const Duration(days: 30)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                _updateStore(storeId, {'subscriptionExpiry': Timestamp.fromDate(picked)});
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}