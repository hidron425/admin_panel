import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'screens/login_screen.dart';
import 'screens/admin_screen.dart';
import 'theme/admin_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await supa.Supabase.initialize(
    url: 'https://cthxobhlihzcehlwruyf.supabase.co',
    anonKey: 'sb_publishable_FjQlbyG5efSoCI7YMOrWSg_9kHwkw5A',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin Panel',
      theme: buildAdminTheme(),
      home: StreamBuilder<supa.AuthState>(
        stream: supa.Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = supa.Supabase.instance.client.auth.currentSession;
          if (session == null) {
            return const LoginScreen();
          }
          return AdminScreen(userEmail: session.user.email ?? '');
        },
      ),
    );
  }
}