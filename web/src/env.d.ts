/// <reference types="astro/client" />
/// <reference types="@cloudflare/workers-types" />

type Runtime = import('@astrojs/cloudflare').Runtime<{
  API: Fetcher;
}>;

declare namespace App {
  interface Locals extends Runtime {}
}

interface ImportMetaEnv {
  readonly PUBLIC_APP_STORE_URL: string;
  readonly PUBLIC_SUPABASE_URL?: string;
  readonly PUBLIC_SUPABASE_PUBLISHABLE_KEY?: string;
  readonly PUBLIC_POSTHOG_KEY?: string;
  readonly PUBLIC_POSTHOG_HOST?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
