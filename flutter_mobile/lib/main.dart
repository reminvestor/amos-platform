import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/config/router.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/providers/theme_provider.dart';
import 'package:amos_mobile/services/crash_reporter.dart';
import 'package:amos_mobile/services/push_notification_service.dart';
import 'package:amos_mobile/services/badge_service.dart';
import 'package:amos_mobile/providers/realtime_provider.dart';
import 'package:amos_mobile/screens/splash/splash_screen.dart';
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

      // Initialize badge service
      await BadgeService.instance.initialize();
      // Clear badge when app starts
      await BadgeService.instance.clearBadge();

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

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const AmosAppWithSplash(),
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

/// Wrapper that shows splash screen during initialization
class AmosAppWithSplash extends ConsumerStatefulWidget {
  const AmosAppWithSplash({super.key});

  @override
  ConsumerState<AmosAppWithSplash> createState() => _AmosAppWithSplashState();
}

class _AmosAppWithSplashState extends ConsumerState<AmosAppWithSplash> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Run initialization and minimum delay in parallel
      await Future.wait([
        _doInitialization(),
        Future.delayed(const Duration(seconds: 2)), // Minimum splash display
      ]);
    } catch (e) {
      // Log error but continue to main app (auth will handle redirect to login)
      AppLogger.error('Splash initialization error: $e');
    }

    // Ensure loading state is cleared before transitioning
    // (handles case where auth check timed out or hung)
    ref.read(authStateProvider.notifier).clearLoadingState();

    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  Future<void> _doInitialization() async {
    try {
      // Check for existing auth session (restores token from storage)
      // Add timeout to prevent hanging on iOS simulator storage issues
      await ref.read(authStateProvider.notifier).checkAuthStatus()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        AppLogger.warning('Auth check timed out during splash');
      });
    } catch (e) {
      // Silently fail - user will be redirected to login
      AppLogger.warning('Auth check failed during splash: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    if (!_initialized) {
      return MaterialApp(
        title: 'AMOS Labs',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        home: const SplashScreen(),
      );
    }

    return const AmosApp();
  }
}

class AmosApp extends ConsumerStatefulWidget {
  const AmosApp({super.key});

  @override
  ConsumerState<AmosApp> createState() => _AmosAppState();
}

class _AmosAppState extends ConsumerState<AmosApp> with WidgetsBindingObserver {
  StreamSubscription<NotificationPayload>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNotificationListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground - clear badge
        BadgeService.instance.clearBadge();
        AppLogger.info('App resumed - badge cleared');
        break;
      case AppLifecycleState.paused:
        // App going to background - set badge to unread count
        final realtimeState = ref.read(realtimeProvider);
        final unreadCount = realtimeState.totalUnreadCount;
        if (unreadCount > 0) {
          BadgeService.instance.updateBadge(unreadCount);
          AppLogger.info('App paused - badge set to $unreadCount');
        }
        break;
      default:
        break;
    }
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
    WidgetsBinding.instance.removeObserver(this);
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
