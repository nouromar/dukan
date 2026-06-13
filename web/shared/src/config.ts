// Mirror of app/dukan/lib/config/business_rules.dart. When the mobile
// constants change, change here too. Each constant names the matching
// Dart symbol in the comment so grep finds both at once.

/**
 * Default ITU country code used when a user types a bare or
 * leading-zero phone number on the login screen. v1 hardcodes Somalia.
 * Mirror of `defaultCountryCode` in `business_rules.dart`.
 */
export const defaultCountryCode = '+252';

/**
 * How long after posting a Sale can the owner void it.
 * Server-enforced in `void_sale` (migration `0010`). Mirror of
 * `saleVoidWindow` in `business_rules.dart`.
 */
export const saleVoidWindowDays = 7;

/**
 * How long after posting a Receive can the owner void it.
 * Server-enforced in `void_receive` (migration `0010`). Mirror of
 * `receiveVoidWindow` in `business_rules.dart`.
 */
export const receiveVoidWindowHours = 24;

/**
 * Page size for history list screens (Sales, Receives, Payments,
 * Expenses). Raise only if real owners complain about pagination.
 * Mirror of `historyPageLimit` in `business_rules.dart`.
 */
export const historyPageLimit = 100;
