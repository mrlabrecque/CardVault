// ─── Sold comps ──────────────────────────────────────────────────────────────
// Uses scrapechain.com — a no-key wrapper around eBay completed items.
// Docs: https://github.com/colindaniels/eBay-sold-items-documentation

// ─── Active listings ─────────────────────────────────────────────────────────
// Uses the official eBay Browse API (OAuth client credentials — no user token).
// Docs: https://developer.ebay.com/api-docs/buy/browse/resources/item_summary/methods/search

const SCRAPECHAIN_URL  = 'https://ebay-api.scrapechain.com/findCompletedItems';
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

const LOOKBACK_DAYS = 90;

export async function searchSoldListings(query: string): Promise<SearchResult> {
  const res = await fetch(SCRAPECHAIN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ keywords: query, max_search_results: 60, remove_outliers: false, category_id: '261328' }),
  });

  if (!res.ok) throw new Error(`scrapechain error ${res.status}: ${await res.text()}`);

  const data = await res.json() as any;

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - LOOKBACK_DAYS);

  const allItems: SoldItem[] = (data.products ?? []).map((p: any) => ({
    itemId:        p.item_id ?? null,
    title:         p.title ?? '',
    price:         { value: String(p.sale_price ?? 0), currency: p.currency ?? 'USD' },
    buyingOptions: resolveBuyingOptions(p.buying_format),
    itemEndDate:   p.date_sold ?? null,
    itemWebUrl:    p.link ?? null,
    imageUrl:      p.image_url ?? null,
    condition:     p.condition ?? '',
  }));

  const items = allItems.filter(item => {
    if (!item.itemEndDate) return true;
    return new Date(item.itemEndDate) >= cutoff;
  });

  const stats: CompsStats = {
    average_price: data.average_price ?? 0,
    median_price:  data.median_price  ?? 0,
    min_price:     data.min_price     ?? 0,
    max_price:     data.max_price     ?? 0,
    total_results: data.total_results ?? items.length,
  };

  return { items, stats };
}

export async function createListing(card: Record<string, unknown>): Promise<object> {
  // TODO: Implement eBay Trading API AddFixedPriceItem call
  console.log(`Creating eBay listing for card: ${card['id']}`);
  return { itemId: null, status: 'not_implemented' };
}
