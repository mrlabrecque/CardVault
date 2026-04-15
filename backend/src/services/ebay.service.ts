// Sold comps via scrapechain.com — a no-key wrapper around eBay completed items.
// Docs: https://github.com/colindaniels/eBay-sold-items-documentation
// POST https://ebay-api.scrapechain.com/findCompletedItems

const SCRAPECHAIN_URL = 'https://ebay-api.scrapechain.com/findCompletedItems';

export interface SoldItem {
  itemId:      string | null;
  title:       string;
  price:       { value: string; currency: string };
  buyingOptions: string[];
  itemEndDate: string | null;
  itemWebUrl:  string | null;
  imageUrl:    string | null;
  condition:   string;
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

function resolveBuyingOptions(buying_format: string | null): string[] {
  const fmt = (buying_format ?? '').toLowerCase();
  if (fmt.includes('auction'))    return ['AUCTION'];
  if (fmt.includes('best offer') || fmt.includes('best_offer')) return ['BEST_OFFER'];
  return ['FIXED_PRICE'];
}

const LOOKBACK_DAYS = 90;

export async function searchSoldListings(query: string): Promise<SearchResult> {
  const res = await fetch(SCRAPECHAIN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ keywords: query, max_search_results: 60, remove_outliers: false }),
  });

  if (!res.ok) throw new Error(`scrapechain error ${res.status}: ${await res.text()}`);

  const data = await res.json() as any;

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - LOOKBACK_DAYS);

  const allItems: SoldItem[] = (data.products ?? []).map((p: any) => ({
    itemId:       p.item_id ?? null,
    title:        p.title ?? '',
    price:        { value: String(p.sale_price ?? 0), currency: p.currency ?? 'USD' },
    buyingOptions: resolveBuyingOptions(p.buying_format),
    itemEndDate:  p.date_sold ?? null,
    itemWebUrl:   p.link ?? null,
    imageUrl:     p.image_url ?? null,
    condition:    p.condition ?? '',
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
