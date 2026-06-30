// Single source of truth for business-rule numerics that the UI
// depends on.
//
// The void windows used to live here as constants; they are now per-shop,
// per-type and arrive on the shop row's `void_settings` (migration 0085),
// parsed into `VoidSettings` (lib/config/void_settings.dart) and read off
// `ShopSummary.voidSettings`. The void_* RPCs re-enforce the same windows
// server-side via `_void_window_days`.

/// Page size for history list screens (Sale, Receive, Payment, Expense).
/// The four screens all paginate against the matching `list_*` RPC;
/// raise this only if real users complain about pagination, not just
/// because it feels small.
const int historyPageLimit = 100;

/// Default ITU country code used when a shopkeeper types a bare or
/// leading-zero phone number on the login screen. v1 hardcodes Somalia
/// because the pilot is Somalia-only; when the second-country shop
/// signs up, this becomes a per-shop / per-OS-locale lookup and the
/// two call sites (`normalizePhoneNumber`, `_phoneController` in
/// `phone_login_screen.dart`) thread through here.
const String defaultCountryCode = '+252';
