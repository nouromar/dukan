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
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';
import 'package:dukan/sync/sync_engine.dart';

// Thresholds resolve from `ConfigResolver` per #376 — defaults
// match the previous hard-coded values (24 h / 20 / 10 min) but
// shops can now tune them via platform_config without a build.

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
  // #377: capture the last sync failure so the card can SHOW it
  // instead of silently looping. Without this the cashier taps
  // Retry, the RPC fails, and they see the same card again with
  // no signal what went wrong (the original "card already says
  // tap Retry" theory turned out to read as a dead-end screen
  // during smoke testing).
  String? _lastSyncError;
  // #377: auto-trigger the first sync on State A — the previous
  // "wait for user tap" design made a normal first launch look
  // like an error screen. Set true once we've attempted (so we
  // don't loop forever on persistent failure).
  bool _autoSyncAttempted = false;

  bool _isFlagFull = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newFlag = useLocalDb(context);
    if (newFlag != _isFlagFull) {
      _isFlagFull = newFlag;
      _hasLocalFuture = newFlag ? _probeHasLocal() : Future.value(true);
      _autoSyncAttempted = false;
      _lastSyncError = null;
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
    if (mounted) {
      setState(() {
        _syncing = true;
        _lastSyncError = null;
      });
    }
    try {
      await engine.fullSync(widget.shop.id, force: true);
      if (!mounted) return;
      _refreshLocalProbe();
    } catch (error) {
      // #377: surface the actual error so the cashier knows WHY
      // the sync failed instead of seeing the same card again
      // with no feedback. The card renders `_lastSyncError`
      // inline so smoke testing can paste it back.
      if (mounted) setState(() => _lastSyncError = error.toString());
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
          // #377: auto-trigger the first sync the first time we
          // land on State A. The previous "wait for user tap"
          // design made a normal first launch look like an error
          // screen. Schedule the auto-attempt via post-frame so
          // we don't setState during build.
          if (!_autoSyncAttempted && !_syncing && _lastSyncError == null) {
            _autoSyncAttempted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _onTapFirstSync();
            });
          }
          return _FirstSyncCard(
            syncing: _syncing,
            onRetry: _onTapFirstSync,
            lastError: _lastSyncError,
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
    // Resolve thresholds from ConfigResolver when present (per
    // #376). Falls back to the defaults baked into the keys when
    // not wired (e.g., test contexts without a resolver in scope).
    ConfigResolver? resolver;
    try {
      resolver = context.read<ConfigResolver>();
    } catch (_) {
      resolver = null;
    }
    final staleHours = resolver?.resolve(ConfigKeys.alertOfflineHours) ??
        ConfigKeys.alertOfflineHours.defaultValue;
    final pendingMax = resolver?.resolve(ConfigKeys.alertPendingThreshold) ??
        ConfigKeys.alertPendingThreshold.defaultValue;
    final rtDownMins =
        resolver?.resolve(ConfigKeys.alertRealtimeDownMinutes) ??
            ConfigKeys.alertRealtimeDownMinutes.defaultValue;
    if (lastSync != null &&
        now.difference(lastSync) > Duration(hours: staleHours)) {
      return lastSync;
    }
    if (queue.pendingCount > pendingMax) {
      // No "since" timestamp for queue-based issues — pick the
      // engine's last sync as the visible time so the banner has
      // a sensible label.
      return lastSync ?? now;
    }
    final rtDown = engine.realtimeDisconnectedAt;
    if (rtDown != null &&
        now.difference(rtDown) > Duration(minutes: rtDownMins)) {
      return rtDown;
    }
    return null;
  }
}

class _FirstSyncCard extends StatelessWidget {
  const _FirstSyncCard({
    required this.syncing,
    required this.onRetry,
    this.lastError,
  });

  final bool syncing;
  final VoidCallback onRetry;
  final String? lastError;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    // Three visual modes per #377:
    //   * syncing: friendly "Setting up your shop..." with a
    //     spinner. This is the typical first-launch path now
    //     that we auto-trigger. Doesn't look like an error.
    //   * lastError != null: the error/dead-end shape — DNS
    //     failure or RPC missing. Shows raw error so smoke
    //     testing can paste it back.
    //   * idle (neither): pre-attempt fallback. Rarely seen now
    //     that auto-trigger is on, but stays as a defensive
    //     state in case the post-frame callback didn't fire.
    if (syncing) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    l.syncFirstTimeLoadingTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.syncFirstTimeLoadingBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final hasError = lastError != null;
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
                      hasError
                          ? Icons.error_outline
                          : Icons.cloud_off_outlined,
                      size: 56,
                      color: hasError
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.syncFirstTimeSetupTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.syncFirstTimeSetupBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (hasError) ...[
                      const SizedBox(height: 12),
                      Text(
                        lastError!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onRetry,
                      child: Text(l.syncFirstTimeSetupRetryButton),
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
