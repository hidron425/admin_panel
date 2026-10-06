import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:intl/intl.dart';
import 'package:admin_panel/utils/audit.dart';
import 'package:admin_panel/utils/app_state.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedMallId;

  String? _selectedUserId;
  String? _selectedUserEmail;
  bool _isBlocked = false;
  final _bonusDescriptionController = TextEditingController();
  final _bonusValueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedMallId = AppState.selectedMallId.value;
    AppState.selectedMallId.addListener(_onMallChanged);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    AppState.selectedMallId.removeListener(_onMallChanged);
    _tabController.dispose();
    _searchController.dispose();
    _bonusDescriptionController.dispose();
    _bonusValueController.dispose();
    super.dispose();
  }

  void _onMallChanged() {
    if (_selectedMallId != AppState.selectedMallId.value) {
      setState(() => _selectedMallId = AppState.selectedMallId.value);
    }
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
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _getUsersStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Ошибка: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final allUsers = snapshot.data!;
              final filtered = allUsers.where((user) {
                if (_searchQuery.isEmpty) return true;
                final email = (user['email'] as String?)?.toLowerCase() ?? '';
                return email.contains(_searchQuery);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(child: Text('Нет пользователей'));
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final data = filtered[index];
                  final userId = data['user_id'] as String? ?? '';
                  final email = data['email'] as String? ?? 'Нет email';
                  final completedSteps = (data['completed_steps'] as num?)?.toInt() ?? 0;
                  final cycleCount = (data['cycle_count'] as num?)?.toInt() ?? 0;
                  final lastActiveRaw = data['last_active'] as String?;
                  final lastActive = lastActiveRaw != null
                      ? DateTime.tryParse(lastActiveRaw)
                      : null;
                  final blocked = data['blocked'] == true;
                  final userMallId = data['selected_mall_id'] as String? ?? '—';

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: ListTile(
                      title: Text(
                        email,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: blocked ? Colors.red : null,
                        ),
                      ),
                      subtitle: Text(
                        'Шагов: $completedSteps | Циклов: $cycleCount\n'
                        'Активен: ${lastActive != null ? DateFormat('dd.MM.yyyy HH:mm').format(lastActive) : 'никогда'}\n'
                        'ТЦ: $userMallId',
                      ),
                      trailing: blocked
                          ? const Chip(
                              label: Text('Заблокирован',
                                  style: TextStyle(color: Colors.white)),
                              backgroundColor: Colors.red,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedUserId = userId;
                          _selectedUserEmail = email;
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

  Stream<List<Map<String, dynamic>>> _getUsersStream() {
    // Supabase stream требует включённого Realtime на таблице user_progress
    if (_selectedMallId != null) {
      return _sb
          .from('user_progress')
          .stream(primaryKey: ['user_id'])
          .eq('selected_mall_id', _selectedMallId!)
          .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
    }
    return _sb
        .from('user_progress')
        .stream(primaryKey: ['user_id'])
        .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
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
          Text(
            'Выбран пользователь: ${_selectedUserEmail ?? _selectedUserId}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
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
          const Text('Выдать бонус пользователю',
              style: TextStyle(fontWeight: FontWeight.bold)),
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
    try {
      await _sb
          .from('user_progress')
          .update({'blocked': block}).eq('user_id', userId);
      AuditLogger.log(
        action: block ? 'block' : 'unblock',
        collection: 'user_progress',
        docId: userId,
        changes: {'blocked': block},
      );
      if (mounted) {
        setState(() => _isBlocked = block);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(block ? 'Пользователь заблокирован' : 'Блокировка снята')),
        );
      }
    } catch (e) {
      debugPrint('❌ _toggleBlock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _sb.from('user_progress').update({
        'completed_steps': 0,
        'used_shop_ids': <String>[],
        'pending_fork_shops': <String>[],
        'last_shop_id': null,
        'is_path_active': false,
        'cycle_count': 0,
      }).eq('user_id', userId);
      AuditLogger.log(
        action: 'reset_progress',
        collection: 'user_progress',
        docId: userId,
        changes: {'completed_steps': 0, 'cycle_count': 0},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Прогресс сброшен')),
        );
      }
    } catch (e) {
      debugPrint('❌ _resetProgress: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _issueBonus(String userId) async {
    try {
      // Читаем текущий массив pending_bonuses
      final data = await _sb
          .from('user_progress')
          .select('pending_bonuses')
          .eq('user_id', userId)
          .maybeSingle();
      if (data == null) return;

      final pending = List<dynamic>.from(data['pending_bonuses'] ?? []);
      pending.add({
        'title': _bonusDescriptionController.text.trim(),
        'message': _bonusDescriptionController.text.trim(),
        'icon': '🎁',
        'value': int.tryParse(_bonusValueController.text) ?? 0,
        'issuedBy': _sb.auth.currentUser?.email ?? 'admin',
        'timestamp': DateTime.now().toIso8601String(),
      });

      await _sb.from('user_progress').update({
        'pending_bonuses': pending,
      }).eq('user_id', userId);

      AuditLogger.log(
        action: 'issue_bonus',
        collection: 'user_progress',
        docId: userId,
        changes: {
          'title': _bonusDescriptionController.text.trim(),
          'value': _bonusValueController.text.trim(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Бонус выдан')),
        );
        _bonusDescriptionController.clear();
        _bonusValueController.clear();
      }
    } catch (e) {
      debugPrint('❌ _issueBonus: $e');
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
            ? 'Управление пользователями (Все ТЦ)'
            : 'Управление пользователями (${_selectedMallId})'),
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