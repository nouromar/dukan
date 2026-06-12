// Single source of truth for business-rule numerics that the UI
// depends on. Values that the backend ALSO depends on (the 7-day void
// window is enforced in migration 0010's void_sale RPC) MUST be kept
// in sync server-side. The matching server constant is named in the
// doc comment per constant — change here AND in the named migration
// or the client-server contract drifts.

/// How long after posting a Sale can the owner void it.
///
/// Server-enforced in `void_sale` (migration `0010`, `v_void_window`).
/// Decision: `docs/decisions.md` Q12.
const Duration saleVoidWindow = Duration(days: 7);

/// How long after posting a Receive can the owner void it. Narrower
/// than the sale window because receive corrections almost always
/// happen the same shift.
///
/// Server-enforced in `void_receive` (migration `0010`).
const Duration receiveVoidWindow = Duration(hours: 24);

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
