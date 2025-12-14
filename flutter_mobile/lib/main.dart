import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/config/router.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/theme_provider.dart';
import 'package:amos_mobile/services/crash_reporter.dart';
import 'package:amos_mobile/utils/logger.dart';

void main() {
  // Catch errors outside Flutter framework (async errors)
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Validate environment configuration (throws in production if misconfigured)
      Env.validateConfiguration();

      // Initialize crash reporting
      await CrashReporter.instance.initialize();

      AppLogger.info('Starting AMOS Labs Mobile');
      AppLogger.info('Environment: ${Env.environment.name}');
      AppLogger.info('API URL: ${Env.apiBaseUrl}');

      // Catch Flutter framework errors
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        CrashReporter.instance.recordFlutterError(details);
      };

      runApp(const ProviderScope(child: AmosApp()));
    },
    (error, stack) {
      CrashReporter.instance.recordError(
        error,
        stackTrace: stack,
        reason: 'Uncaught async error',
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
      title: 'AMOS Labs',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
