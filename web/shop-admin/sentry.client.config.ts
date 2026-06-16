// Browser-side Sentry init. Runs once at page load. No-op when DSN
// is unset (dev + previews without a Sentry project configured).

import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  // Lower traces sample rate while we calibrate; bump later if we
  // start using performance tracing seriously.
  tracesSampleRate: 0.1,
  // Don't bother bundling/inlining the Replay or Profiling pieces
  // unless we explicitly want them — keeps the client bundle small.
  replaysOnErrorSampleRate: 0,
  replaysSessionSampleRate: 0,
  environment: process.env.NODE_ENV,
});
