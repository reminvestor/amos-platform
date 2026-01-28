import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Splash screen shown during app initialization
class SplashScreen extends StatelessWidget {
  final String? loadingMessage;

  const SplashScreen({
    super.key,
    this.loadingMessage,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1a1a2e) : Colors.white;
    final textColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo with fade-in animation
            Image.asset(
              'assets/images/logo-header.png',
              height: 48,
              color: isDark ? Colors.white : const Color(0xFF1a1a2e),
            )
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),

            const SizedBox(height: 48),

            // Loading indicator with pulse animation
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? Colors.white54 : const Color(0xFF1a1a2e).withOpacity(0.5),
                ),
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

            if (loadingMessage != null) ...[
              const SizedBox(height: 24),
              Text(
                loadingMessage!,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                ),
              ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }
}
