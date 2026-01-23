import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/config/router.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/providers/theme_provider.dart';
import 'package:amos_mobile/services/crash_reporter.dart';
import 'package:amos_mobile/services/push_notification_service.dart';
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

      // Create provider container for auth check
      final container = ProviderContainer();

      // Check for existing auth session (restores token from storage)
      await container.read(authStateProvider.notifier).checkAuthStatus();

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const AmosApp(),
        ),
      );
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

class AmosApp extends ConsumerStatefulWidget {
  const AmosApp({super.key});

  @override
  ConsumerState<AmosApp> createState() => _AmosAppState();
}

class _AmosAppState extends ConsumerState<AmosApp> {
  StreamSubscription<NotificationPayload>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    // Listen for notification taps to navigate to the right screen
    _notificationSubscription = PushNotificationService().onNotificationTap.listen((payload) {
      final router = ref.read(routerProvider);

      if (payload.type == NotificationType.directMessage && payload.threadId != null) {
        // Navigate to DM chat
        router.pushNamed('dm-chat', pathParameters: {'threadId': payload.threadId.toString()});
        AppLogger.info('Navigating to DM thread: ${payload.threadId}');
      } else if (payload.type == NotificationType.teamMessage && payload.threadId != null) {
        // Navigate to DM chat (team messages also use threads)
        router.pushNamed('dm-chat', pathParameters: {'threadId': payload.threadId.toString()});
        AppLogger.info('Navigating to thread: ${payload.threadId}');
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
