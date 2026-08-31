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

GitHub Actions deploys this Worker from `.github/workflows/deploy-web.yml` when `web/**` changes on `main`.
Add `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as GitHub repository secrets. The token
should be scoped to the account and have the Edit Cloudflare Workers permission.

On `getkindl.ing`, point the custom domain at this worker (not `kindling-api`).
