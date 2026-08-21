# Kindling API (Cloudflare Worker)

Hono API for screenshot parsing, Google Places and Routes lookup, account deletion, and public
share pages.

## Local

```sh
cd backend
bun install
cp .env.example .dev.vars       # fill in keys (or copy from an existing .env)
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

The iOS target also needs a client-restricted Maps SDK key. Set the
`GOOGLE_MAPS_API_KEY` build setting for the app target; it is injected into
`Info.plist` and is not committed to the repository.

Workers Builds is connected to this Git repo. `kindling-api` lives in `backend/`, so in the Worker go to **Settings → Build** and set:

- **Root directory:** `backend`
- **Deploy command:** `npx wrangler deploy`
- **Non-production branch deploy command:** `npx wrangler versions upload`

If Root directory is left empty, the repository-root `wrangler.jsonc` is the fallback so those default commands still find this Worker.

On the `api.getkindl.ing` custom domain, route API paths to this worker:

- `api.getkindl.ing/ideas*`, `/account*`, `/share*`, `/health*` → `kindling-api`

## Routes

| Method | Path | Auth |
| --- | --- | --- |
| GET | `/health` | none |
| GET | `/places/:id` | none |
| GET | `/places/:id/photo` | none |
| POST | `/routes` | Supabase bearer token |
| GET | `/share/:id` | none (public idea payload for the web funnel) |
| POST | `/ideas` | `x-user-id` header (existing client) |
| DELETE | `/account` | `Authorization: Bearer <supabase jwt>` |
