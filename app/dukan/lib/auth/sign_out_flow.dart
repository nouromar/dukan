// UI-layer sign-out flow. Wraps AuthController.signOut() with:
//   1. A final drain attempt for the offline queue (5s cap).
//   2. A confirm dialog if posts remain unsynced after the drain.
//   3. Clearing in-memory caches that would otherwise leak across
//      users on shared devices (FavoritesCache).
//
// Why a separate helper instead of doing this inside AuthController:
// AuthController has no BuildContext (it's a ChangeNotifier in the
// Provider tree) and shouldn't import Material / show dialogs. Each
// screen that exposes a sign-out action calls confirmSignOut(context)
// instead of context.read<AuthController>().signOut() directly.
//
// On confirm OR empty-queue, queue rows STAY in sqflite. The
// audit-stamping work in Phase 5 makes this safe: each post carries
// `original_actor_user_id`, so when the next signed-in user drains
// the queue, the audit log still credits the original cashier.
// Discarding the queue here would silently lose real sales.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/shared/favorites_cache.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/storage/storage_defaults.dart';

/// Initiates sign-out with the safeguards described above. Returns
/// true if sign-out actually proceeded; false if the cashier
/// cancelled at the confirm dialog.
Future<bool> confirmSignOut(BuildContext context) async {
  final auth = context.read<AuthController>();
  final queue = context.read<OfflineQueueController>();

  // 1. If anything is queued, try to drain it before signing out.
  //    Hard-cap so a slow network can't hang the sign-out flow.
  if (queue.pendingCount > 0) {
    await queue.drainWithTimeout(kSignOutDrainTimeout);
  }

  // 2. Re-check after the drain attempt. If still non-empty, ask.
  if (queue.pendingCount > 0) {
    if (!context.mounted) return false;
    final l = tr(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.signOutPendingDialogTitle),
        content: Text(l.signOutPendingDialogBody(queue.pendingCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l.signOutPendingDialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l.signOutPendingDialogConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
  }

  // 3. Clear in-memory caches that would leak across users on a
  //    shared device. AuthController.signOut() already clears the
  //    persisted AuthStateCache for the outgoing userId.
  FavoritesCache.clear();

  await auth.signOut();
  return true;
}
