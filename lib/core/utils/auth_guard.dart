import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/widgets/auth_dialog.dart';
import '../../providers/app_providers.dart';

class AuthGuard {
  /// Verifies that the user has a registered/authenticated account before hosting/scheduling.
  /// If user is anonymous, opens the AuthDialog.
  static void requireHostAuth(
    BuildContext context,
    WidgetRef ref,
    VoidCallback onAuthorized,
  ) {
    final userState = ref.read(currentUserProvider);
    final user = userState.value;

    if (user != null && user.isRegistered) {
      onAuthorized();
    } else {
      AuthDialog.show(
        context,
        isHostContext: true,
        onAuthenticated: onAuthorized,
      );
    }
  }
}
