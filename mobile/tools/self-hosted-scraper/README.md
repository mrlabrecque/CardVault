# Self-Hosted Sold Comps Scraper

This service runs a local Playwright scraper and exposes a simple HTTP API your Supabase Edge Function can call.

## Endpoints

- `GET /health` -> basic health check
- `POST /sold-listings` -> scrape eBay sold listings

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
      "imageUrl": "https://i.ebayimg.com/...",
      "source": "self_hosted_playwright"
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

## Reduce eBay Blocking

Heroku dyno IPs are frequently challenged by eBay. To improve success rate:

- Configure a residential/datacenter rotating proxy:
  - `SELF_HOSTED_PROXY_SERVER`
  - `SELF_HOSTED_PROXY_USERNAME`
  - `SELF_HOSTED_PROXY_PASSWORD`
- Keep retries enabled:
  - `SELF_HOSTED_ATTEMPTS=3`
  - `SELF_HOSTED_RETRY_BASE_MS=1500`
- Keep cooldown logic in your edge function enabled to avoid repeated fetches.

## TODO

- Add a residential rotating proxy provider and set:
  - `SELF_HOSTED_PROXY_SERVER`
  - `SELF_HOSTED_PROXY_USERNAME`
  - `SELF_HOSTED_PROXY_PASSWORD`

## Edge Function Env

Set these vars for your Supabase function environment:

- `SELF_HOSTED_SCRAPER_URL=http://<host>:8788/sold-listings`
- `SELF_HOSTED_SCRAPER_API_KEY=<same-key-as-env>`

Use your server/LAN/public URL instead of localhost when the edge runtime cannot reach your machine.
