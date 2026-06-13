// Single typed access point for environment variables. Fails fast at
// process start with a clear error if a required var is missing, instead
// of crashing on first request with a confusing "URL is undefined".

import { z } from "zod";

const EnvSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(20),
});

const parsed = EnvSchema.safeParse({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
});

if (!parsed.success) {
  // Format errors as a one-liner so they're easy to spot in Vercel logs.
  const issues = parsed.error.issues
    .map((i) => `${i.path.join(".")}: ${i.message}`)
    .join("; ");
  throw new Error(
    `Missing or invalid environment variables: ${issues}. ` +
      "Copy .env.example to .env.local (local) or set them in Vercel project settings (deployed).",
  );
}

export const env = parsed.data;
