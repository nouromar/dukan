// Compact pill that appears in the app bar of any screen wrapped in
// the OfflineQueueController provider. Renders only when the queue
// has items; tapping triggers an immediate drain attempt (useful
// when the cashier knows connectivity just came back).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/shared/l10n.dart';

class QueueStatusPill extends StatelessWidget {
  const QueueStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<OfflineQueueController>();
    if (queue.pendingCount == 0) return const SizedBox.shrink();
    final l = tr(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: queue.drainNow,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: queue.isDraining
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onErrorContainer,
                      )
                    : Icon(
                        Icons.cloud_off,
                        size: 14,
                        color: theme.colorScheme.onErrorContainer,
                      ),
              ),
              const SizedBox(width: 6),
              Text(
                l.offlineQueuePillLabel(queue.pendingCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
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
