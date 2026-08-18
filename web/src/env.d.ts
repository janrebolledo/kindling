/// <reference types="astro/client" />
/// <reference types="@cloudflare/workers-types" />

type Runtime = import('@astrojs/cloudflare').Runtime<{
  API: Fetcher;
  SESSION: KVNamespace;
  ASSETS: Fetcher;
}>;

declare namespace App {
  interface Locals extends Runtime {}
}

interface ImportMetaEnv {
  readonly PUBLIC_API_URL: string;
  readonly PUBLIC_APP_STORE_URL: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
