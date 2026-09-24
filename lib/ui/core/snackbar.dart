import 'package:flutter/material.dart';

import 'package:lab_05/ui/core/theme.dart';

/// Shows the app's one style of snack bar: floating, rounded, and coloured
/// for errors or successes.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  bool isSuccess = false,
  Duration duration = const Duration(seconds: 4),
  SnackBarAction? action,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: isSuccess
          ? Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            )
          : Text(message),
      backgroundColor: isError
          ? colorScheme.error
          : isSuccess
          ? AppColors.success
          : null,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: duration,
      action: action,
    ),
  );
}

/// Confirms a copy to the clipboard, e.g. "Path copied to clipboard".
void showCopiedSnackBar(BuildContext context, String what) {
  showAppSnackBar(
    context,
    '$what copied to clipboard',
    duration: const Duration(seconds: 1),
  );
}
