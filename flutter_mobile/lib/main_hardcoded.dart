import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:amos_mobile/screens/home/home_screen.dart';
import 'package:amos_mobile/screens/main/main_shell.dart';

void main() {
  runApp(const ProviderScope(child: HardcodedApp()));
}

class HardcodedApp extends StatelessWidget {
  const HardcodedApp({super.key});

  @override
  Widget build(BuildContext context) {
    // BYPASS ALL AUTH - GO STRAIGHT TO HOME
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      title: 'AMOS - Hardcoded',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}