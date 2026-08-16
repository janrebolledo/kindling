# Kindling API (Cloudflare Worker)

Hono API for screenshot parsing, Places lookup, account deletion, and public share pages.

## Local

```sh
cd backend
bun install
cp .dev.vars.example .dev.vars   # fill in keys (or copy from an existing .env)
bun run types
bun run dev
```

Dev server listens on `http://0.0.0.0:3000` so the iOS simulator/device can keep using the LAN URL.

## Deploy

```sh
bun run types
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put GOOGLE_MAPS_API_KEY
npx wrangler secret put SUPABASE_API_KEY
bun run deploy
```

On the `api.getkindl.ing` custom domain, route API paths to this worker:

- `api.getkindl.ing/ideas*`, `/account*`, `/share*`, `/health*` → `kindling-api`

## Routes

| Method | Path | Auth |
| --- | --- | --- |
| GET | `/health` | none |
| GET | `/share/:id` | none (public idea payload for the web funnel) |
| POST | `/ideas` | `x-user-id` header (existing client) |
| DELETE | `/account` | `Authorization: Bearer <supabase jwt>` |
