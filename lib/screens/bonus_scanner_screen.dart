import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

class BonusScannerScreen extends StatefulWidget {
  const BonusScannerScreen({super.key});

  @override
  State<BonusScannerScreen> createState() => _BonusScannerScreenState();
}

class _BonusScannerScreenState extends State<BonusScannerScreen> {
  supa.SupabaseClient get _sb => supa.Supabase.instance.client;
  bool _handled = false;
  String _status = 'Наведите камеру на QR-код клиента';

  Future<void> _onScan(String raw) async {
    if (_handled) return;
    if (!raw.startsWith('SHOPX_BONUS:')) {
      setState(() => _status = 'Это не бонусный QR');
      return;
    }

    _handled = true;
    setState(() => _status = 'Обработка...');

    // Формат: SHOPX_BONUS:<token>:<shop_id>:<rule_id>
    final parts = raw.split(':');
    if (parts.length < 3) {
      setState(() {
        _status = 'Некорректный QR';
        _handled = false;
      });
      return;
    }

    final token = parts[1];
    final shopId = parts[2];

    try {
      // Найти все user_progress, где есть бонус с таким qr_token
      final rows = await _sb
          .from('user_progress')
          .select('user_id, pending_bonuses')
          .not('pending_bonuses', 'is', null);

      Map<String, dynamic>? foundUser;
      int foundIndex = -1;
      Map<String, dynamic>? foundBonus;

      for (final row in (rows as List)) {
        final pending = row['pending_bonuses'] as List?;
        if (pending == null) continue;
        for (int i = 0; i < pending.length; i++) {
          final item = pending[i];
          if (item is Map && item['qr_token'] == token) {
            foundUser = Map<String, dynamic>.from(row);
            foundIndex = i;
            foundBonus = Map<String, dynamic>.from(item);
            break;
          }
        }
        if (foundUser != null) break;
      }

      if (foundUser == null || foundBonus == null) {
        setState(() {
          _status = 'Бонус не найден';
          _handled = false;
        });
        return;
      }

      // Помечаем бонус как used
      final pending = List<dynamic>.from(foundUser['pending_bonuses'] as List);
      final updated = Map<String, dynamic>.from(foundBonus);
      updated['status'] = 'used';
      updated['used_at'] = DateTime.now().toIso8601String();
      updated['used_at_shop'] = shopId;
      pending[foundIndex] = updated;

      await _sb.from('user_progress').update({
        'pending_bonuses': pending,
      }).eq('user_id', foundUser['user_id']);

      setState(() {
        _status = 'Бонус активирован: ${foundBonus?['title'] ?? ""}';
      });

      // Дать возможность сканировать следующий через 3 секунды
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _handled = false;
          _status = 'Наведите камеру на QR-код клиента';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Ошибка: $e';
        _handled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать бонус клиента')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final barcode = capture.barcodes.firstOrNull;
                if (barcode?.rawValue != null) {
                  _onScan(barcode!.rawValue!);
                }
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _status.contains('активирован')
                ? Colors.green.shade100
                : _status.contains('Ошибка') || _status.contains('не найден')
                    ? Colors.red.shade100
                    : Colors.grey.shade200,
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}