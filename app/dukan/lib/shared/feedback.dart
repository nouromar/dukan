import 'package:flutter/material.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/shared/l10n.dart';

void showError(BuildContext context, String message) {
  // Replace any snackbar already showing (e.g. the optimistic "saved" toast)
  // so an error supersedes it immediately instead of queueing behind it.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A deliberately noticeable positive confirmation — brand-green pill with a
/// check icon, floating above the bottom bar. Used after a Sale/Receive SAVE
/// so the cashier gets clear feedback even when no receipt sheet follows
/// (e.g. an offline, queued sale). Replaces any snackbar already showing so
/// rapid consecutive saves don't stack.
void showHappyToast(BuildContext context, String message) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: scheme.onPrimary),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: scheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ),
    );
}

String authInputErrorMessage(BuildContext context, AuthInputIssue issue) {
  final l = tr(context);
  return switch (issue) {
    AuthInputIssue.invalidPhone => l.invalidPhoneMessage,
    AuthInputIssue.invalidEmail => l.invalidEmailMessage,
    AuthInputIssue.missingPendingPhone => l.missingPendingPhoneMessage,
    AuthInputIssue.missingPendingDestination =>
      l.missingPendingDestinationMessage,
    AuthInputIssue.missingShopNames => l.missingShopNamesMessage,
  };
}
