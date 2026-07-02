// Quiet, non-alarming upload indicator in the app bar of any screen
// wrapped in the OfflineQueueController provider.
//
// The queue retries forever in the background (silent, connection- and
// failure-aware), so this is deliberately NOT an alert — no red, no
// popup, no blocking. It's a soft grey "Syncing N" chip that simply
// shows how many posts are still on the device and not yet on the
// server. Its whole job is uninstall insurance: a careful owner /
// support can notice unsent items before wiping the app. Tapping nudges
// an immediate drain (and revives any post the server parked).
//
// Hidden whenever nothing is outstanding.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/shared/l10n.dart';

class QueueStatusPill extends StatelessWidget {
  const QueueStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<OfflineQueueController>();
    // Everything still on the device: actively-retrying (pending) plus
    // the rare parked (server-rejected) post. Both are "not yet on the
    // server", which is what the shopkeeper cares about.
    final outstanding = queue.pendingCount + queue.failedCount;
    if (outstanding == 0) return const SizedBox.shrink();

    final l = tr(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Neutral grey — informational, never alarming.
    final bg = scheme.surfaceContainerHighest;
    final fg = scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        // retryFailed revives any parked post AND drains pending, so one
        // tap does the right thing whatever the mix.
        onTap: queue.retryFailed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: queue.isDraining
                    ? CircularProgressIndicator(strokeWidth: 2, color: fg)
                    : Icon(Icons.cloud_upload_outlined, size: 14, color: fg),
              ),
              const SizedBox(width: 6),
              Text(
                l.offlineQueuePillLabel(outstanding),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
