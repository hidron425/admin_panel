import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BonusRulesScreen extends StatefulWidget {
  const BonusRulesScreen({Key? key}) : super(key: key);

  @override
  State<BonusRulesScreen> createState() => _BonusRulesScreenState();
}

class _BonusRulesScreenState extends State<BonusRulesScreen> {
  final _firestore = FirebaseFirestore.instance;

  Future<void> _addRule() async {
    final sponsorCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final stepsCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить бонусное правило'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: sponsorCtrl, decoration: const InputDecoration(labelText: 'ID магазина-спонсора')),
              TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'ID магазина-бонуса')),
              TextField(controller: stepsCtrl, decoration: const InputDecoration(labelText: 'Шагов (например 5)'), keyboardType: TextInputType.number),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание бонуса')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              await _firestore.collection('bonus_rules').add({
                'sponsorShopId': sponsorCtrl.text.trim(),
                'targetShopId': targetCtrl.text.trim(),
                'requiredSteps': int.tryParse(stepsCtrl.text) ?? 5,
                'bonusDescription': descCtrl.text.trim(),
                'active': true,
              });
              Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  Future<void> _editRule(String id, Map<String, dynamic> data) async {
    final sponsorCtrl = TextEditingController(text: data['sponsorShopId']);
    final targetCtrl = TextEditingController(text: data['targetShopId']);
    final stepsCtrl = TextEditingController(text: data['requiredSteps'].toString());
    final descCtrl = TextEditingController(text: data['bonusDescription']);
    bool active = data['active'] ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Редактировать правило'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: sponsorCtrl, decoration: const InputDecoration(labelText: 'ID спонсора')),
                TextField(controller: targetCtrl, decoration: const InputDecoration(labelText: 'ID бонусного магазина')),
                TextField(controller: stepsCtrl, decoration: const InputDecoration(labelText: 'Шагов'), keyboardType: TextInputType.number),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Описание')),
                SwitchListTile(
                  title: const Text('Активно'),
                  value: active,
                  onChanged: (val) => setStateDialog(() => active = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                await _firestore.collection('bonus_rules').doc(id).update({
                  'sponsorShopId': sponsorCtrl.text.trim(),
                  'targetShopId': targetCtrl.text.trim(),
                  'requiredSteps': int.tryParse(stepsCtrl.text) ?? 5,
                  'bonusDescription': descCtrl.text.trim(),
                  'active': active,
                });
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRule(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить правило?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Да')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestore.collection('bonus_rules').doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
  if (targetShop == null) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color(banner.color), Color(banner.color).withOpacity(0.8)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  // Если есть imageUrl, показываем картинку с трансформацией
  Widget background;
  if (banner.imageUrl.isNotEmpty) {
    final Matrix4 transform = banner.imageTransform != null
        ? Matrix4.fromList(banner.imageTransform!)
        : Matrix4.identity();
    background = ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Transform(
        transform: transform,
        child: Image.network(
          banner.imageUrl,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(banner.color), Color(banner.color).withOpacity(0.8)]),
            ),
          ),
        ),
      ),
    );
  } else {
    background = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color(banner.color), Color(banner.color).withOpacity(0.8)]),
      ),
    );
  }

  return MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: () => _showDialog(context, targetShop!),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              background,
              // Затемняющая подложка для читаемости текста
              Container(color: Colors.black.withOpacity(0.3)),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      banner.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black26)],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      banner.description,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}