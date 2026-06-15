// Minimal CSV helpers. We deliberately don't pull in a library — the
// data shapes we export are simple (strings / numbers / dates / bools)
// and the escaping rules fit in 15 lines. Adds RFC 4180 quoting only
// when a field actually needs it (contains a comma, quote, newline,
// or leading/trailing whitespace).
//
// Values that come back from Supabase as numeric strings are passed
// through unchanged — toCsvCell formats numbers + Date instances.

function escapeCell(raw: unknown): string {
  if (raw === null || raw === undefined) return "";
  let s: string;
  if (raw instanceof Date) {
    s = raw.toISOString();
  } else if (typeof raw === "number") {
    s = Number.isFinite(raw) ? raw.toString() : "";
  } else if (typeof raw === "boolean") {
    s = raw ? "true" : "false";
  } else {
    s = String(raw);
  }
  if (/[",\n\r]/.test(s) || /^\s|\s$/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

export function toCsv(headers: string[], rows: unknown[][]): string {
  const out: string[] = [];
  out.push(headers.map(escapeCell).join(","));
  for (const row of rows) {
    out.push(row.map(escapeCell).join(","));
  }
  // Excel + LibreOffice are happy with \n; CRLF is the strictly
  // RFC-compliant choice but adds no value here.
  return out.join("\n");
}

/**
 * Build a filename like `dukan-pilot-shop-sales-2026-06-15.csv`.
 * Shop name is lower-cased and ASCII-only-slugged so the output is
 * safe across browsers/OSes.
 */
export function csvFilename(shopName: string, module: string): string {
  const slug = shopName
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  const today = new Date().toISOString().slice(0, 10);
  return `dukan-${slug || "shop"}-${module}-${today}.csv`;
}
