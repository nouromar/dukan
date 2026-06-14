import 'package:flutter/material.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/shared/l10n.dart';

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
