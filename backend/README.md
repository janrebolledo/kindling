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
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put GOOGLE_MAPS_API_KEY
npx wrangler secret put SUPABASE_API_KEY
bun run deploy
```

The iOS target also needs a client-restricted Maps SDK key. Set the
`GOOGLE_MAPS_API_KEY` build setting for the app target; it is injected into
`Info.plist` and is not committed to the repository.

GitHub Actions deploys this Worker from `.github/workflows/deploy.yml` on every push to `main`.
Add `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as GitHub repository secrets. The token
should be scoped to the account and have the Edit Cloudflare Workers permission.

The repository-root `wrangler.jsonc` remains a fallback for local or dashboard deployments.

The API Worker owns the `api.getkindl.ing` custom domain via `backend/wrangler.jsonc`.
Cloudflare provisions the DNS record and certificate during deployment. Its API paths are:

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
