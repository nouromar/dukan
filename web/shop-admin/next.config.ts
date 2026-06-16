import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";
import { withSentryConfig } from "@sentry/nextjs";

// next-intl plugin: points at our i18n/request.ts where per-request
// locale + messages get resolved.
const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");

const nextConfig: NextConfig = {
  /* config options here */
};

// Wrap with Sentry first; next-intl wraps the result. The wrappers
// compose, but the order matters — Sentry needs to see the raw
// nextConfig so it can inject its instrumentation files.
export default withNextIntl(
  withSentryConfig(nextConfig, {
    // Silent builds when the auth token isn't set (e.g. local dev,
    // PR previews) — Sentry's source-map upload is skipped, the
    // app still ships unaffected.
    silent: true,
    org: process.env.SENTRY_ORG,
    project: process.env.SENTRY_PROJECT,
    authToken: process.env.SENTRY_AUTH_TOKEN,
    // Don't tunnel — keeps the bundle slim. Enable later if browser
    // ad-blockers start swallowing reports.
    tunnelRoute: undefined,
    // Tree-shake the Sentry SDK on routes we know don't need it.
    widenClientFileUpload: true,
    disableLogger: true,
  }),
);
