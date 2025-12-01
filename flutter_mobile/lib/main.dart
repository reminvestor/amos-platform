import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/config/router.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/theme_provider.dart';
import 'package:amos_mobile/utils/logger.dart';

void main() {
  // Catch errors outside Flutter framework (async errors)
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      // Catch Flutter framework errors
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        AppLogger.error(
          'Flutter Error',
          error: details.exception,
          stackTrace: details.stack,
        );
      };

      runApp(const ProviderScope(child: AmosApp()));
    },
    (error, stack) {
      AppLogger.error(
        'Uncaught Error',
        error: error,
        stackTrace: stack,
      );
    },
  );
}

class AmosApp extends ConsumerWidget {
  const AmosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AMOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
