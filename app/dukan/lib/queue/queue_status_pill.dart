// Compact pill that appears in the app bar of any screen wrapped in
// the OfflineQueueController provider. Two states:
//
//   * SYNCING (pending posts, none failed) — soft error-container pill,
//     "Syncing N"; tapping drains immediately (useful when the cashier
//     knows connectivity just came back).
//   * NOT SENT (any failed_permanent posts) — a LOUD solid-red alarm,
//     "N not sent — retry". These are sales/receives that gave up after
//     the retry cap and are stranded on the device. This must never be
//     silent — an unnoticed stranded post is lost on reinstall. Tapping
//     resets them to pending and retries.
//
// Renders nothing only when there is genuinely nothing outstanding.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/shared/l10n.dart';

class QueueStatusPill extends StatelessWidget {
  const QueueStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<OfflineQueueController>();
    final failed = queue.failedCount;
    if (queue.pendingCount == 0 && failed == 0) {
      return const SizedBox.shrink();
    }
    final l = tr(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Failed posts dominate: they're the data-loss risk, so they get the
    // loud solid-red alarm and own the tap (retry). Otherwise the softer
    // "syncing" treatment.
    final alarm = failed > 0;
    final bg = alarm ? scheme.error : scheme.errorContainer;
    final fg = alarm ? scheme.onError : scheme.onErrorContainer;
    final label = alarm
        ? l.offlineQueueFailedLabel(failed)
        : l.offlineQueuePillLabel(queue.pendingCount);
    final onTap = alarm ? queue.retryFailed : queue.drainNow;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
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
                    : Icon(
                        alarm ? Icons.sync_problem : Icons.cloud_off,
                        size: 14,
                        color: fg,
                      ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
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
