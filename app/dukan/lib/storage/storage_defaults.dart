// Hard-coded defaults for queue + cache safeguards (Phase 2).
//
// These move to the hierarchical `platform_config` table in Phase 3
// (defaults → org → shop → device). Keeping them in one file means
// the Phase 3 migration is a single search/replace.

/// SOFT threshold on the number of `pending`-state posts. The queue
/// NEVER drops a durable post to save space (queued posts are ~1 KB
/// each; even thousands are trivial on-device, and a dropped post is a
/// lost sale). Crossing this threshold only logs a one-time Sentry
/// warning for observability — "why isn't the queue draining?" — it does
/// not evict anything. Configurable per shop via `queue_max_pending`.
const int kQueueMaxPending = 10000;

/// DEPRECATED — no longer used. The queue is never-expiring: transient
/// failures retry forever and only a genuine server reject parks a post
/// (see OfflineQueueController). Kept so the `queue_max_attempts` config
/// key resolves; remove once that key is retired.
const int kQueueMaxAttempts = 50;

/// Total budget for the cache_entry table in megabytes. On every
/// `CacheDao.put` that exceeds this, the DAO runs LRU eviction
/// (expired entries first, then `last_read_at ASC`) until under
/// budget.
const int kCacheBudgetMb = 100;

/// Drain attempt timeout used during sign-out. We try one final
/// `drainNow()` capped at this duration so a slow network doesn't
/// hang the sign-out flow; if the queue is non-empty after the
/// timeout, the confirm dialog fires.
const Duration kSignOutDrainTimeout = Duration(seconds: 5);

/// Convenience byte-count derived from [kCacheBudgetMb].
const int kCacheBudgetBytes = kCacheBudgetMb * 1024 * 1024;

/// Size budget for the on-device bono image cache (BonoImageCache). Once the
/// cached bonos exceed this, LRU eviction drops the oldest ALREADY-UPLOADED
/// entries (re-fetchable from Storage); not-yet-uploaded bonos are never
/// evicted. ~50 MB ≈ 200 bonos at ~150–300 KB each. Override per shop via the
/// `bono_cache_budget_mb` config key.
const int kBonoCacheBudgetMb = 50;

/// Convenience byte-count derived from [kBonoCacheBudgetMb].
const int kBonoCacheBudgetBytes = kBonoCacheBudgetMb * 1024 * 1024;
