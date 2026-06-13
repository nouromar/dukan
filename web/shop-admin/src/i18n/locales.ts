// Single source of truth for the locales we ship. Adding a new
// language means: append it here, drop a matching catalog into
// messages/<code>.json, and add it to <LanguageSwitcher />.

export const LOCALES = ["en", "so"] as const;
export type Locale = (typeof LOCALES)[number];

export const DEFAULT_LOCALE: Locale = "en";

export const LOCALE_LABELS: Record<Locale, string> = {
  en: "English",
  so: "Soomaali",
};

export const LOCALE_COOKIE = "locale";

export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && (LOCALES as readonly string[]).includes(value);
}
