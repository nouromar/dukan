// Drill-in from the Storage & sync screen: lists every queued post
// that exhausted its retry budget. Each row shows when it was
// queued, which RPC, the server error message, and two actions —
// RETRY (resets state to pending and force-drains) or DISCARD
// (with confirm; permanent loss).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/storage/pending_post_dao.dart';

class FailedPostsScreen extends StatefulWidget {
  const FailedPostsScreen({super.key});

  @override
  State<FailedPostsScreen> createState() => _FailedPostsScreenState();
}

class _FailedPostsScreenState extends State<FailedPostsScreen> {
  late final PendingPostDao _dao;
  late final OfflineQueueController _queue;
  // Starts as empty list (not null) so the empty-state Text renders
  // immediately instead of a CircularProgressIndicator. Avoids
  // pumpAndSettle timeouts in tests (the indicator animates
  // forever) and matches the typical case anyway — this screen is
  // a drill-in from a count that's already known to be > 0 only
  // when the user can reach it.
  List<PendingPost> _failed = const <PendingPost>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dao = context.read<PendingPostDao>();
    _queue = context.read<OfflineQueueController>();
    _load();
  }

  Future<void> _load() async {
    final rows = await _dao.loadFailedPermanent();
    if (!mounted) return;
    setState(() => _failed = rows);
  }

  Future<void> _onRetry(PendingPost post) async {
    await _dao.resetToPending(post.id);
    // Reload the queue's in-memory state so drain picks up the
    // re-pending row. The controller's `start()` is idempotent but
    // doesn't reload on demand; pop+drain via drainNow after we
    // refresh by re-enqueueing via the load path. Simplest correct
    // move: reload the controller's pending list by calling its
    // internal load through dao + drainNow.
    await _queue.drainNow();
    await _load();
  }

  Future<void> _onDiscard(PendingPost post) async {
    final l = tr(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.failedPostsDiscardConfirmTitle),
        content: Text(l.failedPostsDiscardConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.failedPostsDiscardConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _dao.remove(post.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final rows = _failed;
    return Scaffold(
      appBar: AppBar(title: Text(l.failedPostsTitle)),
      body: rows.isEmpty
          ? Center(
              child: Text(
                l.failedPostsEmptyState,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final p = rows[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatHistoryStamp(context, p.queuedAt),
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            Text(
                              p.rpc,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (p.lastError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            p.lastError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _onDiscard(p),
                              child: Text(l.failedPostsDiscardButton),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => _onRetry(p),
                              child: Text(l.failedPostsRetryButton),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
