import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Don't call async operations from build()
    // Initialize theme asynchronously after app starts
    _initializeTheme();
    return ThemeMode.system;
  }

  static const _key = 'theme_mode';

  void _initializeTheme() {
    // Schedule async initialization without blocking build()
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final themeString = prefs.getString(_key);
        if (themeString != null) {
          state = ThemeMode.values.firstWhere(
            (e) => e.name == themeString,
            orElse: () => ThemeMode.system,
          );
        }
      } catch (e) {
        // Silently fail on web if SharedPreferences isn't available
        // App will just use system theme
      }
    });
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  void toggleTheme() {
    if (state == ThemeMode.light) {
      setThemeMode(ThemeMode.dark);
    } else {
      setThemeMode(ThemeMode.light);
    }
  }
}
