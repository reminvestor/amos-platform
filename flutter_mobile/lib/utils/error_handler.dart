import 'package:flutter/material.dart';
import 'package:amos_mobile/utils/exceptions.dart';

/// Mixin for handling errors in widgets
mixin ErrorHandler {
  /// Show error message to user via SnackBar
  void showError(
    BuildContext context,
    dynamic error, {
    String? fallbackMessage,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!context.mounted) return;

    String message = _getErrorMessage(error, fallbackMessage);

    // Capture ScaffoldMessenger before showing snackbar to avoid context issues
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            scaffoldMessenger.hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Show success message to user via SnackBar
  void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ),
    );
  }

  /// Show error dialog with more details
  Future<void> showErrorDialog(
    BuildContext context,
    dynamic error, {
    String? title,
    String? fallbackMessage,
  }) async {
    if (!context.mounted) return;

    String message = _getErrorMessage(error, fallbackMessage);

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Text(title ?? 'Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Get user-friendly error message from exception
  String _getErrorMessage(dynamic error, String? fallbackMessage) {
    if (error is NetworkException) {
      return error.message;
    } else if (error is AuthException) {
      return error.message;
    } else if (error is ValidationException) {
      return error.message;
    } else if (error is ServerException) {
      return error.message;
    } else if (error is TimeoutException) {
      return error.message;
    } else if (error is AppException) {
      return error.message;
    } else if (error is String) {
      return error;
    } else {
      return fallbackMessage ?? 'An unexpected error occurred. Please try again.';
    }
  }
}
