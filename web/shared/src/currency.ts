// Money formatting. Mirrors the mobile app's formatter shape so a
// $10.50 sale reads the same on the receipt, the dashboard, and the
// export. USD goes through Intl (native ISO-4217 support); SLSH
// (Somaliland Shilling) is not a recognised ISO code, so we render a
// plain "SLSH 12,500" with grouped thousands.
//
// Locale is taken from the user's i18n locale ("en" or "so"); both
// use Western Arabic digits in the portal regardless of source
// language, matching the design doc's "always render numbers in
// digits the cashier can read at a glance."

export function formatMoney(
  amount: number | null | undefined,
  currency: string,
  locale: string = "en",
): string {
  const value = amount ?? 0;
  if (currency === "USD") {
    try {
      return new Intl.NumberFormat(locale, {
        style: "currency",
        currency: "USD",
      }).format(value);
    } catch {
      return `$${value.toFixed(2)}`;
    }
  }
  // SLSH and other non-ISO codes — show grouped thousands with the
  // code as a prefix.
  const grouped = new Intl.NumberFormat(locale, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(value);
  return `${currency} ${grouped}`;
}

/**
 * Counter formatting (transaction count, low-stock item count, etc).
 * Just grouped thousands per locale; never a currency symbol.
 */
export function formatCount(
  value: number | null | undefined,
  locale: string = "en",
): string {
  return new Intl.NumberFormat(locale).format(value ?? 0);
}
