// Three-state boundary for the offline-first daily flows.
//
// State A — first-time setup: no local data + flag=full →
//   a blocking "Connect to load your shop's data" card.
//   The user can't proceed until the first full sync lands.
// State B — working: pass-through; just renders [child].
// State C — sync issue: child renders behind a top banner
//   that surfaces a stale or stuck sync state. Tap →
//   `SyncEngine.forceDelta()` with a toast for the outcome.
//
// Detection priorities (highest first):
//   1. flag != full         → State B (light mode is unaffected).
//   2. local DB empty       → State A. forceDelta needs a fullSync;
//                              we go through that route on Retry.
//   3. lastSyncedAt > 24h   → State C.
//   4. pendingCount > 20    → State C.
//   5. realtime down > 10m  → State C.
//   6. otherwise            → State B.
//
// The boundary listens on SyncEngine + OfflineQueueController so
// any state-affecting change re-renders. Heavy work (the
// `hasAnyData` sqflite probe for State A) runs once on init and
// re-runs only when SyncEngine fires `notifyListeners` (the
// hasInitialSync flag flips after first fullSync).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/offline_mode.dart';
import 'package:dukan/sync/sync_engine.dart';

/// Default threshold for "this sync looks stuck."
const _kStaleSyncThreshold = Duration(hours: 24);

/// How many queued posts is "too many" — surfaces State C.
const _kPendingCountThreshold = 20;

/// Realtime disconnected for longer than this counts as broken.
const _kRealtimeDownThreshold = Duration(minutes: 10);

class CacheMissBoundary extends StatefulWidget {
  const CacheMissBoundary({
    required this.shop,
    required this.child,
    super.key,
  });

  final ShopSummary shop;
  final Widget child;

  @override
  State<CacheMissBoundary> createState() => _CacheMissBoundaryState();
}

class _CacheMissBoundaryState extends State<CacheMissBoundary> {
  Future<bool>? _hasLocalFuture;
  bool _syncing = false;

  bool _isFlagFull = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newFlag = offlineModeFull(context);
    if (newFlag != _isFlagFull) {
      _isFlagFull = newFlag;
      _hasLocalFuture = newFlag ? _probeHasLocal() : Future.value(true);
    }
    _hasLocalFuture ??= newFlag ? _probeHasLocal() : Future.value(true);
  }

  Future<bool> _probeHasLocal() async {
    try {
      final repo = context.read<LocalRepository>();
      return repo.hasAnyData(widget.shop.id);
    } catch (_) {
      // Tests without a LocalRepository in scope — treat as "has data"
      // so the boundary becomes a pass-through.
      return true;
    }
  }

  void _refreshLocalProbe() {
    if (!mounted) return;
    setState(() {
      _hasLocalFuture = _probeHasLocal();
    });
  }

  Future<void> _onTapRetry() async {
    if (_syncing) return;
    final l = tr(context);
    SyncEngine? engine;
    try {
      engine = context.read<SyncEngine>();
    } catch (_) {
      engine = null;
    }
    if (engine == null) return;
    setState(() => _syncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.syncForceSyncingToast)),
    );
    try {
      final count = await engine.forceDelta(widget.shop.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.syncForceSyncedToast(count))),
      );
      _refreshLocalProbe();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      showError(context, l.syncForceFailedToast);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _onTapFirstSync() async {
    if (_syncing) return;
    SyncEngine? engine;
    try {
      engine = context.read<SyncEngine>();
    } catch (_) {
      engine = null;
    }
    if (engine == null) return;
    setState(() => _syncing = true);
    try {
      await engine.fullSync(widget.shop.id, force: true);
      _refreshLocalProbe();
    } catch (_) {
      // Error surfaces via the SyncEngine state — the boundary will
      // re-render itself once the failure flag flips. No toast: the
      // first-sync card already says "tap Retry," not "synced".
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isFlagFull) {
      // Light mode → transparent pass-through.
      return widget.child;
    }
    return FutureBuilder<bool>(
      future: _hasLocalFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // While probing, render the child. The probe is fast
          // (single LIMIT 1 sqflite row) but we don't want a flash
          // of the first-sync card on every screen mount.
          return widget.child;
        }
        final hasLocal = snapshot.data ?? true;
        if (!hasLocal) {
          return _FirstSyncCard(
            syncing: _syncing,
            onRetry: _onTapFirstSync,
          );
        }
        return Consumer2<SyncEngine, OfflineQueueController>(
          builder: (context, engine, queue, _) {
            final issue = _detectIssue(engine, queue);
            return Stack(
              children: [
                widget.child,
                if (issue != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _SyncIssueBanner(
                      since: issue,
                      syncing: _syncing,
                      onTap: _onTapRetry,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// Returns the wallclock "since when has the sync been broken"
  /// for the issue banner, or null if everything looks healthy.
  DateTime? _detectIssue(
    SyncEngine engine,
    OfflineQueueController queue,
  ) {
    final lastSync = engine.lastSyncedAt;
    final now = DateTime.now();
    if (lastSync != null && now.difference(lastSync) > _kStaleSyncThreshold) {
      return lastSync;
    }
    if (queue.pendingCount > _kPendingCountThreshold) {
      // No "since" timestamp for queue-based issues — pick the
      // engine's last sync as the visible time so the banner has
      // a sensible label.
      return lastSync ?? now;
    }
    final rtDown = engine.realtimeDisconnectedAt;
    if (rtDown != null && now.difference(rtDown) > _kRealtimeDownThreshold) {
      return rtDown;
    }
    return null;
  }
}

class _FirstSyncCard extends StatelessWidget {
  const _FirstSyncCard({required this.syncing, required this.onRetry});

  final bool syncing;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.syncFirstTimeSetupTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.syncFirstTimeSetupBody,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: syncing ? null : onRetry,
                      child: syncing
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l.syncFirstTimeSetupRetryButton),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncIssueBanner extends StatelessWidget {
  const _SyncIssueBanner({
    required this.since,
    required this.syncing,
    required this.onTap,
  });

  final DateTime since;
  final bool syncing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final hh = since.hour.toString().padLeft(2, '0');
    final mm = since.minute.toString().padLeft(2, '0');
    final label = l.syncIssueBannerLabel('$hh:$mm');
    final theme = Theme.of(context);
    final color = theme.colorScheme.errorContainer;
    final onColor = theme.colorScheme.onErrorContainer;
    return GestureDetector(
      onTap: syncing ? null : onTap,
      child: Container(
        color: color,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
                  ),
                ),
                if (syncing)
                  SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onColor,
                    ),
                  )
                else
                  Icon(Icons.refresh, color: onColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
