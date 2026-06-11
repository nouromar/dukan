// Tiny per-process cache for the favorites that Sale and Receive
// render on entry — the response from `searchItems(query: '')`.
//
// Why this exists: tapping Sale on Home mounts the screen and *then*
// fires the searchItems RPC. On Hargeisa 4G that's 800ms–2s of dead
// screen before any favorite tile is visible — recurring on every
// Sale entry. The cache pattern is:
//
//   1. When the Today card mounts on Home, prefetch favorites for
//      both screens in the background (no UI blocking).
//   2. When Sale or Receive mounts, read from the cache and render
//      instantly. Trigger a background refresh if the entry is stale.
//   3. Every successful searchItems(query: '') response updates the
//      cache (cheap — same code path, no extra RPC).
//
// In-memory only — survives navigation, not app restart. TTL is short
// (30s) so stale data never lasts longer than one cashier session
// between flows.
//
// Static singleton on purpose: no Provider wiring needed and tests
// can `clear()` in setUp. Adding Provider here would touch every
// existing test that mounts Sale or Receive.

import 'package:dukan/api/types.dart';

class FavoritesCache {
  FavoritesCache._();

  static final Map<String, _Entry> _store = <String, _Entry>{};

  /// Time after which an entry is considered stale and will trigger
  /// a background refresh. Reads still return the stale value so
  /// the UI is never blocked on a refetch.
  static const Duration ttl = Duration(seconds: 30);

  /// Returns the cached favorites for (shopId, screen), or null when
  /// nothing has been cached. Stale entries are still returned —
  /// callers should trigger a refresh via [put] when they re-fetch.
  static List<ItemSearchResult>? get(String shopId, String screen) {
    final entry = _store['$shopId:$screen'];
    return entry?.value;
  }

  /// True when the entry is missing or older than [ttl]. Callers use
  /// this to decide whether to trigger a background refresh after
  /// rendering the cached value.
  static bool isStale(String shopId, String screen) {
    final entry = _store['$shopId:$screen'];
    if (entry == null) return true;
    return entry.isStale();
  }

  /// Records a fresh favorites list. Mirror this from every
  /// successful searchItems(query: '') response so the cache stays
  /// hot for the next visit.
  static void put(
    String shopId,
    String screen,
    List<ItemSearchResult> value,
  ) {
    _store['$shopId:$screen'] = _Entry(
      List<ItemSearchResult>.unmodifiable(value),
      _nowOverride?.call() ?? DateTime.now(),
    );
  }

  /// Clear all cached entries. Tests use this in setUp so cross-test
  /// state doesn't leak.
  static void clear() => _store.clear();

  static DateTime Function()? _nowOverride;

  /// Visible for testing — inject a deterministic clock.
  static set nowForTesting(DateTime Function()? clock) {
    _nowOverride = clock;
  }
}

class _Entry {
  _Entry(this.value, this.savedAt);
  final List<ItemSearchResult> value;
  final DateTime savedAt;

  bool isStale() {
    final now = FavoritesCache._nowOverride?.call() ?? DateTime.now();
    return now.difference(savedAt) > FavoritesCache.ttl;
  }
}
