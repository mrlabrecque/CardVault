# Self-Hosted Sold Comps Scraper

This service runs a local Playwright scraper and exposes a simple HTTP API your Supabase Edge Function can call.

By default it opens **[130 Point](https://130point.com/sales/)** (aggregated eBay sold data). Set `SELF_HOSTED_SALES_SOURCE=ebay` only if you need direct eBay HTML (often blocked).

## Endpoints

- `GET /health` -> basic health check (includes `salesSource`, `asyncJobs`)
- `POST /sold-listings` -> scrape sold comps (130 Point by default)
  - **`{ "query": "...", "maxItems": 40, "async": true }`** → **202** with `{ jobId, pollUrl }` so **Heroku avoids the ~30s router timeout** (H12). Poll **`GET pollUrl`** with the same `x-api-key` until `status` is `done` or `failed`.
  - Omit `async` → synchronous response (fine locally; **avoid on Heroku** for long Playwright runs).

Request body:

```json
{
  "query": "2025 Donruss Optic Brock Purdy #1",
  "maxItems": 40
}
```

Response body:

```json
{
  "query": "...",
  "count": 40,
  "elapsedMs": 4200,
  "items": [
    {
      "title": "...",
      "price": 75.0,
      "soldDate": "2026-05-01T00:00:00.000Z",
      "itemWebUrl": "https://www.ebay.com/itm/...",
      "imageUrl": "https://...",
      "source": "self_hosted_130point"
    }
  ]
}
```

## Local Run

1. `cd mobile/tools/self-hosted-scraper`
2. `cp .env.example .env` and set `SELF_HOSTED_SCRAPER_API_KEY`
3. `npm install`
4. `npm run install:browsers`
5. `set -a && source .env && set +a && npm run dev`

The service listens on `http://localhost:8788` by default.

## Reliability notes

130 Point sits behind **Cloudflare**. Datacenter IPs (including Heroku) usually need a **residential proxy** for Playwright. The browser already routes **all 130point traffic** through the proxy when configured — this is separate from Decodo’s **Scraper API** (used by the Edge function for eBay HTML only).

Proxy configuration (first match wins):

| Variables | Use case |
|-----------|----------|
| `SELF_HOSTED_PROXY_SERVER` + `USERNAME` / `PASSWORD` | Generic HTTP proxy |
| `DECODO_PROXY_SERVER` + `DECODO_PROXY_USERNAME` / `DECODO_PROXY_PASSWORD` | Decodo **residential gateway** (not the same as `DECODO_SCRAPER_*` in Supabase) |
| `SELF_HOSTED_PROXY_URL` or `DECODO_PROXY_URL` | Single URL, e.g. `http://user:pass@host:port` |

Optional: `SELF_HOSTED_REQUIRE_PROXY=true` makes 130point scrapes fail fast if no proxy is set (useful to catch misconfigured Heroku env).

Session rotation + header jitter:

- `SELF_HOSTED_PROXY_ROTATE=true` (default) appends/updates a sticky `session-<id>` token in proxy usernames per attempt/query so retries are more likely to use a different exit IP/session.
- User-Agent, viewport, `accept-language`, and a few navigation headers are jittered per attempt/query to reduce repeat fingerprints.

`GET /health` includes `proxyConfigured: true|false` and `proxyRotate: true|false` so you can confirm runtime behavior (no secrets returned).

To fall back to scraping eBay directly (not recommended):

- `SELF_HOSTED_SALES_SOURCE=ebay`

## Reduce blocking (proxies)

Heroku / datacenter IPs are often challenged. To improve success rate:

- Set **one** of the proxy styles in the table above on the **Heroku app** that runs this scraper (not only in Supabase).
- Keep retries enabled:
  - `SELF_HOSTED_ATTEMPTS=3`
  - `SELF_HOSTED_RETRY_BASE_MS=1500`
- Keep cooldown logic in your edge function enabled to avoid repeated fetches.

## Edge Function Env

Set these vars for your Supabase function environment:

- `SELF_HOSTED_SCRAPER_URL=http://<host>:8788/sold-listings`
- `SELF_HOSTED_SCRAPER_API_KEY=<same-key-as-env>`

Use your server/LAN/public URL instead of localhost when the edge runtime cannot reach your machine.

## Heroku: apply Decodo (or other) proxy in one step

From this directory, with the [Heroku CLI](https://devcenter.heroku.com/articles/heroku-cli) logged in:

1. Put proxy values in `.env` (see `.env.example`) **or** export them in your shell.
2. Run:

```bash
export HEROKU_APP=your-heroku-app-name
npm run heroku:set-proxy
```

This runs `heroku config:set` with `DECODO_PROXY_*` or `SELF_HOSTED_PROXY_*` (same rules as `server.js`). Restart is automatic on next deploy; to restart without deploy: `heroku restart -a $HEROKU_APP`.

Verify: `curl -s "https://$HEROKU_APP.herokuapp.com/health"` → `"proxyConfigured": true`.
