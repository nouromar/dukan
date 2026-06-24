// Shopkeeper-facing storage & sync status screen. Read-only by design
// (per CLAUDE.md decision-free daily use) plus two action buttons —
// "Sync now" forces a drain, "Free up space" clears caches without
// touching queued sales. One device-level toggle: "Sync only on
// Wi-Fi" (persists the preference; OfflineQueueController doesn't
// honor it yet — Phase 5 wiring).
//
// Numbers come from existing infrastructure:
//   * Queue count / drain status: OfflineQueueController.
//   * Failed-permanent count + cache size: DAO queries (cheap).
//   * Cache budget: ConfigResolver.resolve(cacheBudgetMb).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/storage/cache_dao.dart';
import 'package:dukan/storage/failed_posts_screen.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/sync_engine.dart';
import 'package:dukan/sync/use_local_db.dart';

class StorageSyncScreen extends StatefulWidget {
  const StorageSyncScreen({super.key});

  @override
  State<StorageSyncScreen> createState() => _StorageSyncScreenState();
}

class _StorageSyncScreenState extends State<StorageSyncScreen> {
  late final PendingPostDao _pendingDao;
  late final CacheDao _cacheDao;
  late final OfflineQueueController _queue;
  ConfigResolver? _resolver;

  int _failedCount = 0;
  int _pendingBytes = 0;
  int _cacheBytes = 0;
  int _cacheEntries = 0;
  bool _refreshing = false;
  bool _syncing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pendingDao = context.read<PendingPostDao>();
    _cacheDao = context.read<CacheDao>();
    _queue = context.read<OfflineQueueController>();
    try {
      _resolver = context.read<ConfigResolver>();
    } catch (_) {
      _resolver = null;
    }
    _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final results = await Future.wait<dynamic>([
        _pendingDao.countFailedPermanent(),
        _pendingDao.totalBytes(),
        _cacheDao.stats(),
      ]);
      if (!mounted) return;
      setState(() {
        _failedCount = results[0] as int;
        _pendingBytes = results[1] as int;
        final cacheStats =
            results[2] as ({int totalBytes, int entryCount});
        _cacheBytes = cacheStats.totalBytes;
        _cacheEntries = cacheStats.entryCount;
      });
    } finally {
      _refreshing = false;
    }
  }

  /// #387: bidirectional sync. PUSH the queue first (so any
  /// drained server-side rows show up in the subsequent delta),
  /// then PULL via `SyncEngine.forceDelta` (ON mode only — OFF
  /// has no engine running per #383).
  Future<void> _onSyncNow() async {
    final l = tr(context);
    final useLocal = useLocalDb(context);
    SyncEngine? engine;
    String? shopId;
    if (useLocal) {
      try {
        engine = context.read<SyncEngine>();
        shopId = context.read<AuthController>().selectedShop?.id;
      } catch (_) {
        engine = null;
      }
    }
    setState(() => _syncing = true);
    final beforePending = _queue.pendingCount;
    var pulled = 0;
    try {
      await _queue.drainNow();
      if (engine != null && shopId != null) {
        try {
          pulled = await engine.forceDelta(shopId);
        } catch (_) {
          // Pull failure is non-fatal — the push half may still
          // have landed something useful. Toast covers it via
          // the pushed count.
        }
      }
      if (!mounted) return;
      final pushed = beforePending - _queue.pendingCount;
      final msg = _buildSyncToast(l, pushed: pushed, pulled: pulled);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      showError(context, l.storageSyncSyncFailedToast);
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _refresh();
    }
  }

  String _buildSyncToast(
    AppLocalizations l, {
    required int pushed,
    required int pulled,
  }) {
    if (pushed == 0 && pulled == 0) return l.storageSyncAlreadyUpToDateToast;
    if (pushed > 0 && pulled == 0) return l.storageSyncPushedToast(pushed);
    if (pushed == 0 && pulled > 0) return l.storageSyncPulledToast(pulled);
    return l.storageSyncPushedAndPulledToast(pushed, pulled);
  }

  /// #381: Re-download all server data. Used when the catalog
  /// drifted (e.g., a backend RPC was extended after the device
  /// did its initial full sync, so delta-sync misses historical
  /// rows). Bypasses the 24h server-side rate limit with
  /// `force: true`.
  Future<void> _onResyncAll() async {
    final l = tr(context);
    SyncEngine? engine;
    String? shopId;
    try {
      engine = context.read<SyncEngine>();
      shopId = context.read<AuthController>().selectedShop?.id;
    } catch (_) {
      engine = null;
    }
    if (engine == null || shopId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.storageSyncResyncConfirmTitle),
        content: Text(l.storageSyncResyncConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.storageSyncResyncConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _syncing = true);
    try {
      await engine.fullSync(shopId, force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.storageSyncResyncDoneToast)),
      );
    } catch (error) {
      if (!mounted) return;
      showError(context, '${l.storageSyncResyncFailedToast}\n$error');
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _refresh();
    }
  }

  /// #387: mode-aware destructive action.
  /// * useLocalDb=false → "Free up space": clear the small SWR
  ///   cache_entry table. Mild.
  /// * useLocalDb=true → "Reset local data": typed-confirm wipe
  ///   of all local_* mirror tables. Drains the queue first; aborts
  ///   if anything failed permanently so the cashier can review.
  Future<void> _onFreeUpSpaceOrReset() async {
    if (useLocalDb(context)) {
      await _onResetLocalData();
    } else {
      await _onClearCache();
    }
  }

  Future<void> _onClearCache() async {
    final l = tr(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.storageSyncFreeUpSpaceConfirmTitle),
        content: Text(l.storageSyncFreeUpSpaceConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.storageSyncFreeUpSpaceConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _cacheDao.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.storageSyncCacheClearedToast)),
    );
    await _refresh();
  }

  Future<void> _onResetLocalData() async {
    final l = tr(context);
    SyncEngine? engine;
    LocalRepository? repo;
    String? shopId;
    try {
      engine = context.read<SyncEngine>();
      repo = context.read<LocalRepository>();
      shopId = context.read<AuthController>().selectedShop?.id;
    } catch (_) {
      engine = null;
    }
    if (engine == null || repo == null || shopId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ResetLocalDataDialog(
        connected: _isConnected(),
        pendingCount: _queue.pendingCount,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _syncing = true);
    try {
      // 1. Drain anything queued so the cashier doesn't lose work.
      if (_queue.pendingCount > 0) {
        await _queue.drainNow();
      }
      // 2. Did anything fail permanently during drain? Abort.
      final failedAfter = await _pendingDao.countFailedPermanent();
      if (failedAfter > _failedCount) {
        final newlyFailed = failedAfter - _failedCount;
        if (!mounted) return;
        showError(
          context,
          l.storageSyncResetPendingFailedBlocker(newlyFailed),
        );
        return;
      }
      // 3. Wipe local mirror.
      await repo.wipeAllLocalData(shopId);
      // 4. Force a fresh full sync so the user lands in a clean
      // state (or sees the first-time-setup card via
      // CacheMissBoundary if offline).
      await engine.fullSync(shopId, force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.storageSyncResetDoneToast)),
      );
    } catch (error) {
      if (!mounted) return;
      showError(context, '${l.storageSyncResetFailedToast}\n$error');
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _refresh();
    }
  }

  Future<void> _onToggleWifiOnly(bool wifiOnly) async {
    final r = _resolver;
    if (r == null) return;
    await r.setDeviceOverride(
      ConfigKeys.syncMode.name,
      wifiOnly ? 'wifi' : 'auto',
    );
    if (mounted) setState(() {});
  }

  bool _isConnected() {
    if (_queue.pendingCount == 0) return true;
    final last = _queue.lastDrainSuccessAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < const Duration(seconds: 60);
  }

  int _budgetBytes() {
    final r = _resolver;
    if (r == null) return 100 * 1024 * 1024;
    return r.resolve(ConfigKeys.cacheBudgetMb) * 1024 * 1024;
  }

  bool _wifiOnly() {
    final r = _resolver;
    if (r == null) return false;
    return r.resolve(ConfigKeys.syncMode) == 'wifi';
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    // Watch the queue so pending count + lastDrainSuccessAt updates
    // re-render the screen live.
    context.watch<OfflineQueueController>();
    final pending = _queue.pendingCount;
    final connected = _isConnected();
    final last = _queue.lastDrainSuccessAt;
    final totalBytes = _pendingBytes + _cacheBytes;
    final budget = _budgetBytes();

    return Scaffold(
      appBar: AppBar(title: Text(l.storageSyncTitle)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Connection status ---------------------------------------
            Row(
              children: [
                Icon(
                  connected ? Icons.cloud_done : Icons.cloud_off,
                  color: connected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  connected
                      ? l.storageSyncStatusConnected
                      : l.storageSyncStatusOffline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _LabelValueRow(
              label: l.storageSyncLastSyncedLabel,
              value: last == null
                  ? l.storageSyncLastSyncedNever
                  : formatHistoryStamp(context, last),
            ),
            const SizedBox(height: 24),

            // ---- Pending / failed ---------------------------------------
            _LabelValueRow(
              label: l.storageSyncPendingSalesLabel,
              value: l.storageSyncPendingCount(pending),
            ),
            if (_failedCount > 0) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FailedPostsScreen(),
                    ),
                  );
                  if (mounted) await _refresh();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.storageSyncFailedPermanentlyLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        l.storageSyncFailedPermanentlyCount(_failedCount),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // ---- Storage usage ------------------------------------------
            _LabelValueRow(
              label: l.storageSyncStorageUsedLabel,
              value: '${_formatBytes(totalBytes)} / ${_formatBytes(budget)}',
            ),
            const SizedBox(height: 4),
            // Static usage bar (not LinearProgressIndicator) so
            // widget tests don't hang on its perpetual ticker.
            // pumpAndSettle on M3 LinearProgressIndicator never
            // returns under fake-async; FractionallySizedBox is a
            // single layout pass with the same visual.
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                height: 4,
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: budget == 0
                      ? 0
                      : (totalBytes / budget).clamp(0.0, 1.0),
                  child: Container(color: theme.colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _BreakdownRow(
              label: l.storageSyncStorageBreakdownPending,
              value: _formatBytes(_pendingBytes),
            ),
            _BreakdownRow(
              label: l.storageSyncStorageBreakdownCached,
              value: '${_formatBytes(_cacheBytes)} '
                  '($_cacheEntries)',
            ),
            const SizedBox(height: 24),

            // ---- Actions -------------------------------------------------
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _syncing ? null : _onSyncNow,
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(l.storageSyncSyncNowButton),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _syncing ? null : _onFreeUpSpaceOrReset,
                    icon: Icon(
                      useLocalDb(context)
                          ? Icons.delete_forever_outlined
                          : Icons.cleaning_services_outlined,
                      color: useLocalDb(context)
                          ? theme.colorScheme.error
                          : null,
                    ),
                    label: Text(
                      useLocalDb(context)
                          ? l.storageSyncResetButton
                          : l.storageSyncFreeUpSpaceButton,
                      style: useLocalDb(context)
                          ? TextStyle(color: theme.colorScheme.error)
                          : null,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      side: useLocalDb(context)
                          ? BorderSide(color: theme.colorScheme.error)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            // #381 + #387: Re-download is only useful in ON mode
            // (SyncEngine drives the local mirror). In OFF mode
            // the engine isn't started — clicking would no-op.
            if (useLocalDb(context)) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _syncing ? null : _onResyncAll,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(l.storageSyncResyncAllButton),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),

            // ---- Settings -----------------------------------------------
            Text(
              l.storageSyncSettingsHeader,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            // TODO(#36X): OfflineQueueController doesn't honor sync_mode
            // yet — the toggle persists the preference but drain still
            // fires on any connection. Wire `connectivity_plus` in
            // Phase 5 so the drain pauses when on cellular and the
            // toggle is enabled.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.storageSyncWifiOnlyLabel),
              value: _wifiOnly(),
              onChanged: _resolver == null ? null : _onToggleWifiOnly,
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// #387: typed-confirmation dialog for "Reset local data". User
/// must type the word `RESET` (English) / `TIRTIR` (Somali) to
/// enable the destructive button. Blocked entirely when phone
/// looks offline AND there are pending posts — the cashier must
/// drain first so they don't lose work.
class _ResetLocalDataDialog extends StatefulWidget {
  const _ResetLocalDataDialog({
    required this.connected,
    required this.pendingCount,
  });

  final bool connected;
  final int pendingCount;

  @override
  State<_ResetLocalDataDialog> createState() => _ResetLocalDataDialogState();
}

class _ResetLocalDataDialogState extends State<_ResetLocalDataDialog> {
  final _controller = TextEditingController();
  String _typed = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _blocked => !widget.connected && widget.pendingCount > 0;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final magicWord = l.storageSyncResetTypeWord;
    final canConfirm =
        !_blocked && _typed.trim().toUpperCase() == magicWord.toUpperCase();
    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: theme.colorScheme.error,
        size: 40,
      ),
      title: Text(
        l.storageSyncResetConfirmTitle,
        style: TextStyle(color: theme.colorScheme.error),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.storageSyncResetConfirmBody),
          const SizedBox(height: 16),
          if (_blocked)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l.storageSyncResetOfflineBlocker,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            )
          else ...[
            Text(
              l.storageSyncResetTypePrompt,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: (v) => setState(() => _typed = v),
              decoration: InputDecoration(
                hintText: magicWord,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed:
              canConfirm ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: Text(l.storageSyncResetConfirmAction),
        ),
      ],
    );
  }
}
