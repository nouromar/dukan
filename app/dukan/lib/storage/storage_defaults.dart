// Hard-coded defaults for queue + cache safeguards (Phase 2).
//
// These move to the hierarchical `platform_config` table in Phase 3
// (defaults → org → shop → device). Keeping them in one file means
// the Phase 3 migration is a single search/replace.

/// Maximum number of `pending`-state posts the queue will hold.
/// On overflow, the oldest pending post is dropped (with a Sentry
/// log + one-time toast to the cashier).
const int kQueueMaxPending = 200;

/// Number of failed drain attempts before a post is moved to the
/// terminal `failed_permanent` state. The drain loop stops retrying
/// once a post hits this; the user can manually retry from the
/// Storage & sync screen (Phase 4) which resets the state to
/// `pending`.
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
