// ─── Sold comps ──────────────────────────────────────────────────────────────
// Uses scrapechain.com — a no-key wrapper around eBay completed items.
// Docs: https://github.com/colindaniels/eBay-sold-items-documentation

// ─── Active listings ─────────────────────────────────────────────────────────
// Uses the official eBay Browse API (OAuth client credentials — no user token).
// Docs: https://developer.ebay.com/api-docs/buy/browse/resources/item_summary/methods/search

import sql from '../db/db';

const SCRAPECHAIN_URL  = 'https://ebay-api.scrapechain.com/findCompletedItems';

const USER_AGENTS = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
];

function randomUserAgent(): string {
  return USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)];
}
const EBAY_OAUTH_URL   = 'https://api.ebay.com/identity/v1/oauth2/token';
const EBAY_BROWSE_URL  = 'https://api.ebay.com/buy/browse/v1/item_summary/search';

// Sports Trading Cards category on eBay
const EBAY_CATEGORY_ID = '261328';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface SoldItem {
  itemId:       string | null;
  title:        string;
  price:        { value: string; currency: string };
  buyingOptions: string[];
  itemEndDate:  string | null;
  itemWebUrl:   string | null;
  imageUrl:     string | null;
  condition:    string;
}

export interface CompsStats {
  average_price:  number;
  median_price:   number;
  min_price:      number;
  max_price:      number;
  total_results:  number;
}

export interface SearchResult {
  items: SoldItem[];
  stats: CompsStats;
}

export interface ActiveListing {
  itemId:      string;
  title:       string;
  price:       number;
  currency:    string;
  listingType: 'AUCTION' | 'FIXED_PRICE';
  url:         string;
  imageUrl:    string | null;
  condition:   string | null;
}

// ─── App token cache ──────────────────────────────────────────────────────────

let _cachedToken: string | null = null;
let _tokenExpiresAt = 0;

async function getAppToken(): Promise<string> {
  if (_cachedToken && Date.now() < _tokenExpiresAt) return _cachedToken;

  const appId   = process.env.EBAY_APP_ID!;
  const certId  = process.env.EBAY_CERT_ID!;
  const encoded = Buffer.from(`${appId}:${certId}`).toString('base64');

  const res = await fetch(EBAY_OAUTH_URL, {
    method: 'POST',
    headers: {
      'Content-Type':  'application/x-www-form-urlencoded',
      'Authorization': `Basic ${encoded}`,
    },
    body: 'grant_type=client_credentials&scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope',
  });

  if (!res.ok) throw new Error(`eBay OAuth failed (${res.status}): ${await res.text()}`);

  const data = await res.json() as any;
  _cachedToken    = data.access_token;
  // Expire 5 min before actual expiry to be safe
  _tokenExpiresAt = Date.now() + (data.expires_in - 300) * 1000;
  return _cachedToken!;
}

// ─── Active listing search ────────────────────────────────────────────────────

/**
 * Search eBay active listings (BIN + auctions) for a given query at or below
 * maxPrice. Returns up to 20 results sorted by price ascending.
 */
export async function searchActiveListings(query: string, maxPrice: number): Promise<ActiveListing[]> {
  const token = await getAppToken();

  const params = new URLSearchParams({
    q:           query,
    category_ids: EBAY_CATEGORY_ID,
    filter:      `price:[..${maxPrice}],priceCurrency:USD,conditions:{NEW|USED_EXCELLENT|USED_GOOD|UNSPECIFIED}`,
    sort:        'price',
    limit:       '20',
  });

  const res = await fetch(`${EBAY_BROWSE_URL}?${params}`, {
    headers: {
      Authorization:          `Bearer ${token}`,
      'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US',
      'Content-Type':         'application/json',
    },
  });

  if (!res.ok) throw new Error(`eBay Browse API error (${res.status}): ${await res.text()}`);

  const data = await res.json() as any;
  const summaries: any[] = data.itemSummaries ?? [];

  return summaries.map(item => ({
    itemId:      item.itemId ?? '',
    title:       item.title ?? '',
    price:       parseFloat(item.price?.value ?? '0'),
    currency:    item.price?.currency ?? 'USD',
    listingType: (item.buyingOptions ?? []).includes('AUCTION') ? 'AUCTION' : 'FIXED_PRICE',
    url:         item.itemWebUrl ?? '',
    imageUrl:    item.image?.imageUrl ?? null,
    condition:   item.condition ?? null,
  }));
}

// ─── Sold comps search ────────────────────────────────────────────────────────

function resolveBuyingOptions(buying_format: string | null): string[] {
  const fmt = (buying_format ?? '').toLowerCase();
  if (fmt.includes('auction'))                              return ['AUCTION'];
  if (fmt.includes('best offer') || fmt.includes('best_offer')) return ['BEST_OFFER'];
  return ['FIXED_PRICE'];
}

const LOOKBACK_DAYS   = 90;
const CACHE_TTL_HOURS = 24;
const MAX_RETRIES     = 3;
const RETRY_BASE_MS   = 2000;

async function fetchFromScrapechain(query: string): Promise<any> {
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const res = await fetch(SCRAPECHAIN_URL, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json', 'User-Agent': randomUserAgent() },
        body:    JSON.stringify({ keywords: query, max_search_results: 60, remove_outliers: false, category_id: '261328' }),
      });
      if (!res.ok) throw new Error(`scrapechain error ${res.status}: ${await res.text()}`);
      return await res.json();
    } catch (e: any) {
      if (attempt === MAX_RETRIES) throw e;
      const delay = RETRY_BASE_MS * Math.pow(2, attempt - 1);
      console.warn(`[ebay] scrapechain attempt ${attempt} failed — retrying in ${delay}ms: ${e.message}`);
      await new Promise(r => setTimeout(r, delay));
    }
  }
}

function parseItems(data: any): SoldItem[] {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - LOOKBACK_DAYS);

  return (data.products ?? [])
    .map((p: any) => ({
      itemId:        p.item_id ?? null,
      title:         p.title ?? '',
      price:         { value: String(p.sale_price ?? 0), currency: p.currency ?? 'USD' },
      buyingOptions: resolveBuyingOptions(p.buying_format),
      itemEndDate:   p.date_sold ?? null,
      itemWebUrl:    p.link ?? null,
      imageUrl:      p.image_url ?? null,
      condition:     p.condition ?? '',
    }))
    .filter((item: SoldItem) => !item.itemEndDate || new Date(item.itemEndDate) >= cutoff);
}

export async function searchSoldListings(query: string): Promise<SearchResult> {
  // Check cache first
  const [cached] = await sql<{ items: any[]; fetched_at: Date }[]>`
    SELECT items, fetched_at FROM comps_cache WHERE query = ${query}
  `;

  const cacheAge = cached
    ? (Date.now() - new Date(cached.fetched_at).getTime()) / 3600000
    : Infinity;

  if (cached && cacheAge < CACHE_TTL_HOURS) {
    console.log(`[ebay] cache hit for "${query}" (${cacheAge.toFixed(1)}h old)`);
    const items = cached.items as SoldItem[];
    return { items, stats: computeCacheStats(items) };
  }

  // Fetch fresh data
  let data: any;
  try {
    data = await fetchFromScrapechain(query);
  } catch (e: any) {
    // Return stale cache if available rather than failing hard
    if (cached) {
      console.warn(`[ebay] fetch failed, returning stale cache (${cacheAge.toFixed(1)}h old): ${e.message}`);
      const items = cached.items as SoldItem[];
      return { items, stats: computeCacheStats(items), stale: true } as any;
    }
    throw e;
  }

  const items = parseItems(data);

  // Upsert into cache
  await sql`
    INSERT INTO comps_cache (query, items, fetched_at)
    VALUES (${query}, ${sql.json(items as any)}, now())
    ON CONFLICT (query) DO UPDATE SET items = EXCLUDED.items, fetched_at = now()
  `;

  const stats: CompsStats = {
    average_price: data.average_price ?? 0,
    median_price:  data.median_price  ?? 0,
    min_price:     data.min_price     ?? 0,
    max_price:     data.max_price     ?? 0,
    total_results: data.total_results ?? items.length,
  };

  return { items, stats };
}

function computeCacheStats(items: SoldItem[]): CompsStats {
  const prices = items
    .map(i => parseFloat(i.price.value))
    .filter(p => p > 0)
    .sort((a, b) => a - b);
  if (!prices.length) return { average_price: 0, median_price: 0, min_price: 0, max_price: 0, total_results: 0 };
  const sum = prices.reduce((s, p) => s + p, 0);
  const mid = Math.floor(prices.length / 2);
  return {
    average_price: sum / prices.length,
    median_price:  prices.length % 2 === 0 ? (prices[mid - 1] + prices[mid]) / 2 : prices[mid],
    min_price:     prices[0],
    max_price:     prices[prices.length - 1],
    total_results: items.length,
  };
}

export async function createListing(card: Record<string, unknown>): Promise<object> {
  // TODO: Implement eBay Trading API AddFixedPriceItem call
  console.log(`Creating eBay listing for card: ${card['id']}`);
  return { itemId: null, status: 'not_implemented' };
}
