# Kindling web (Cloudflare Worker)

Astro site for getkindl.ing: marketing pages and public share links (`/s/:id`).

## Local

```sh
cd web
bun install
bun run dev
```

Dev server listens on `http://0.0.0.0:4321`.

## Deploy

```sh
bun run deploy
```

That runs `astro build` then `wrangler deploy`. Share pages call `kindling-api` over the `API` service binding, not the public `api.getkindl.ing` URL.

Workers Builds is connected to this Git repo. `kindling-web` lives in `web/`, so in the Worker go to **Settings → Build** and set:

- **Root directory:** `web`
- **Build command:** `bun run build` (or `npm run build`)
- **Deploy command:** `npx wrangler deploy`
- **Non-production branch deploy command:** `npx wrangler versions upload`

Do not leave Root directory empty. The repository-root `wrangler.jsonc` is for `kindling-api` and will fail this Worker with a name mismatch.

On `getkindl.ing`, point the custom domain at this worker (not `kindling-api`).

Production deploys run on pushes to `main` (`npx wrangler deploy`). Pull request commits only upload preview versions.
