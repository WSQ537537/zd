import 'package:flutter/material.dart';
import 'login.dart';
import 'exam.dart';
import 'examdetail.dart';
import 'aichat.dart';


import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final bool loggedIn = prefs.getString('userInfo') != null;
  runApp(MyApp(initialRoute: loggedIn ? '/exam' : '/login'));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '考试应用',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF2196F3),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
        ),
      ),
      initialRoute: initialRoute,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/login':
            return MaterialPageRoute(builder: (_) => const LoginPage());
          case '/exam':
            return MaterialPageRoute(builder: (_) => const ExamPage());
          case '/aichat':
            return MaterialPageRoute(builder: (_) => const AiChatPage());
          
          case '/examdetail':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (context) => ExamDetail(
                paperId: args?['paperId'] ?? '',
                account: args?['account'] ?? '',
              ),
            );
          default:
            return MaterialPageRoute(
              builder: (_) => const LoginPage(),
            );
        }
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
