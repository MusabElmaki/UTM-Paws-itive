import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/report_animal_screen.dart';
import 'screens/report_success_screen.dart';
import 'theme/app_theme.dart';
import 'screens/animal_profile_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/notification_screen.dart';
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
        '/home': (context) => const HomeScreen(),
        '/report': (context) => const ReportAnimalScreen(),
        '/success': (context) => const ReportSuccessScreen(),
        '/animal-profile': (context) => const AnimalProfileScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/notifications': (context) =>
    const NotificationScreen(),
        '/edit-profile': (context) =>
    const EditProfileScreen(),
    '/leaderboard': (context) =>
    const LeaderboardScreen(),
 
      },
    );
  }
}