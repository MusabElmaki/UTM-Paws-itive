import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/report_animal_screen.dart';
import 'screens/report_success_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  runApp(const PawsitiveApp());
}

class PawsitiveApp extends StatelessWidget {
  const PawsitiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UTM Paws-itive',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/report': (context) => const ReportAnimalScreen(),
        '/success': (context) => const ReportSuccessScreen(),
      },
    );
  }
}