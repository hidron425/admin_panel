import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:admin_panel/utils/audit.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Для вкладки «Действия»
  String? _selectedUserId;
  final _bonusDescriptionController = TextEditingController();
  final _bonusValueController = TextEditingController();
  bool _isBlocked = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _bonusDescriptionController.dispose();
    _bonusValueController.dispose();
    super.dispose();
  }

  // ---------- Вкладка «Пользователи» ----------
  Widget _buildUsersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Поиск по email',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('user_progress').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Ошибка: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs.where((doc) {
                if (_searchQuery.isEmpty) return true;
                final email = (doc.data() as Map<String, dynamic>)['email'] as String? ?? '';
                return email.toLowerCase().contains(_searchQuery);
              }).toList();

              if (docs.isEmpty) {
                return const Center(child: Text('Нет пользователей'));
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final email = data['email'] as String? ?? 'Нет email';
                  final userId = docs[index].id;
                  final completedSteps = data['completedSteps'] ?? 0;
                  final cycleCount = data['cycleCount'] ?? 0;
                  final lastActive = (data['lastActive'] as Timestamp?)?.toDate();
                  final blocked = data['blocked'] == true;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: ListTile(
                      title: Text(email, style: TextStyle(fontWeight: FontWeight.bold, color: blocked ? Colors.red : null)),
                      subtitle: Text(
                        'Шагов: $completedSteps | Циклов: $cycleCount\n'
                        'Активен: ${lastActive != null ? DateFormat('dd.MM.yyyy HH:mm').format(lastActive) : 'никогда'}',
                      ),
                      trailing: blocked
                          ? const Chip(label: Text('Заблокирован', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedUserId = userId;
                          _isBlocked = blocked;
                          _bonusDescriptionController.clear();
                          _bonusValueController.clear();
                          _tabController.animateTo(1);
                        });
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- Вкладка «Действия» ----------
  Widget _buildActionsTab() {
    if (_selectedUserId == null) {
      return const Center(
        child: Text('Выберите пользователя на вкладке «Пользователи»'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Выбран пользователь: $_selectedUserId',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Блокировка / разблокировка
          Row(
            children: [
              Text(_isBlocked ? 'Пользователь заблокирован' : 'Пользователь активен'),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _toggleBlock(_selectedUserId!, !_isBlocked),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBlocked ? Colors.green : Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(_isBlocked ? 'Разблокировать' : 'Заблокировать'),
              ),
            ],
          ),
          const Divider(height: 32),

          // Сброс прогресса
          ElevatedButton.icon(
            onPressed: () => _resetProgress(_selectedUserId!),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Сбросить прогресс'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
          const Divider(height: 32),

          // Выдача бонуса
          const Text('Выдать бонус пользователю', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _bonusDescriptionController,
            decoration: const InputDecoration(
              labelText: 'Описание бонуса',
              hintText: 'Скидка 10% на следующую покупку',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bonusValueController,
            decoration: const InputDecoration(
              labelText: 'Значение (опционально)',
              hintText: '10',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: () {
                if (_bonusDescriptionController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Введите описание бонуса')),
                  );
                  return;
                }
                _issueBonus(_selectedUserId!);
              },
              icon: const Icon(Icons.card_giftcard),
              label: const Text('Выдать бонус'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Бизнес-логика ----------
  Future<void> _toggleBlock(String userId, bool block) async {
    final action = block ? 'block' : 'unblock';
    await _firestore.collection('user_progress').doc(userId).update({'blocked': block});
    AuditLogger.log(
      action: action,
      collection: 'user_progress',
      docId: userId,
      changes: {'blocked': block},
    );
    setState(() => _isBlocked = block);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(block ? 'Пользователь заблокирован' : 'Блокировка снята')),
      );
    }
  }

  Future<void> _resetProgress(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить прогресс?'),
        content: const Text('Все данные о прохождении квеста будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сбросить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    await _firestore.collection('user_progress').doc(userId).update({
      'completedSteps': 0,
      'usedShopIds': [],
      'pendingForkShops': [],
      'lastShopId': null,
      'isPathActive': false,
      'cycleCount': 0,
    });
    AuditLogger.log(
      action: 'reset_progress',
      collection: 'user_progress',
      docId: userId,
      changes: {'completedSteps': 0, 'cycleCount': 0},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Прогресс сброшен')),
      );
    }
  }

  Future<void> _issueBonus(String userId) async {
    final bonusData = {
      'title': _bonusDescriptionController.text.trim(),
      'message': _bonusDescriptionController.text.trim(),
      'icon': '🎁',
      'value': int.tryParse(_bonusValueController.text) ?? 0,
      'issuedBy': FirebaseAuth.instance.currentUser?.email ?? 'admin',
      'timestamp': FieldValue.serverTimestamp(),
    };
    await _firestore.collection('user_progress').doc(userId).update({
      'pendingBonuses': FieldValue.arrayUnion([bonusData]),
    });
    AuditLogger.log(
      action: 'issue_bonus',
      collection: 'user_progress',
      docId: userId,
      changes: bonusData,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Бонус выдан')),
      );
      _bonusDescriptionController.clear();
      _bonusValueController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление пользователями'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Пользователи'),
            Tab(text: 'Действия'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersTab(),
          _buildActionsTab(),
        ],
      ),
    );
  }
}