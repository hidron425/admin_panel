import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:admin_panel/utils/audit.dart';
import 'package:admin_panel/utils/app_state.dart';

class AllStoresScreen extends StatefulWidget {
  const AllStoresScreen({Key? key}) : super(key: key);

  @override
  State<AllStoresScreen> createState() => _AllStoresScreenState();
}

class _AllStoresScreenState extends State<AllStoresScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  Future<void> _updateStore(String storeId, Map<String, dynamic> data) async {
    try {
      await _sb.from('shops').update(data).eq('firestore_id', storeId);
      AuditLogger.log(
        action: 'update',
        collection: 'shops',
        docId: storeId,
        changes: data,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сохранено')),
        );
      }
    } catch (e) {
      print('❌ _updateStore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppState.selectedMallId,
      builder: (context, selectedMallId, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Все магазины')),
          body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadStores(selectedMallId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Ошибка: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final stores = snapshot.data ?? [];
              if (stores.isEmpty) {
                return const Center(child: Text('Нет магазинов'));
              }
              return ListView.builder(
                itemCount: stores.length,
                itemBuilder: (context, index) {
                  final data = stores[index];
                  final storeId = data['firestore_id'] as String? ?? '';
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
                                initialValue: (data['push_credits'] ?? 0).toString(),
                                decoration: const InputDecoration(labelText: 'Кредиты пушей'),
                                keyboardType: TextInputType.number,
                                onChanged: (value) {
                                  final int? credits = int.tryParse(value);
                                  if (credits != null) _updateStore(storeId, {'push_credits': credits});
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: data['subscription_plan'] ?? 'start',
                                decoration: const InputDecoration(labelText: 'Тарифный план'),
                                items: const [
                                  DropdownMenuItem(value: 'start', child: Text('Start')),
                                  DropdownMenuItem(value: 'business', child: Text('Business')),
                                  DropdownMenuItem(value: 'premium', child: Text('Premium')),
                                  DropdownMenuItem(value: 'corp', child: Text('Corp')),
                                ],
                                onChanged: (value) => _updateStore(storeId, {'subscription_plan': value}),
                              ),
                              const SizedBox(height: 12),
                              ListTile(
                                title: const Text('Подписка истекает'),
                                subtitle: Text(
                                  data['subscription_expiry'] != null
                                      ? DateTime.parse(data['subscription_expiry'].toString())
                                          .toLocal()
                                          .toString()
                                          .split(' ')[0]
                                      : 'Не установлена',
                                ),
                                trailing: const Icon(Icons.calendar_today),
                                onTap: () async {
                                  final current = data['subscription_expiry'] != null
                                      ? DateTime.parse(data['subscription_expiry'].toString())
                                      : DateTime.now().add(const Duration(days: 30));
                                  DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: current,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) {
                                    _updateStore(storeId, {
                                      'subscription_expiry': picked.toIso8601String(),
                                    });
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
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadStores(String? mallId) async {
    var query = _sb.from('shops').select();
    if (mallId != null && mallId.isNotEmpty) {
      query = query.eq('mall_id', mallId);
    }
    final data = await query.order('name', ascending: true);
    return (data as List).map((json) => Map<String, dynamic>.from(json)).toList();
  }
}