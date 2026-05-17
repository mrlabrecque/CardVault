/**
 * eBay Browse API — client-credentials OAuth + active listings search (trading cards category).
 */

const EBAY_API_BASE_URL = 'https://api.ebay.com';
const EBAY_IDENTITY_URL = 'https://api.ebay.com/identity/v1/oauth2/token';

export type EbayActiveListingRow = {
  ebay_item_id: string | null;
  title: string;
  price: number;
  /** Raw buying option label from Browse API (wishlist matcher uses substring checks). */
  buying_format_raw: string;
  listing_type: 'AUCTION' | 'FIXED_PRICE' | 'BEST_OFFER';
  url: string | null;
  image_url: string | null;
  /** ISO-8601 from Browse API `itemEndDate` when present. */
  itemEndDate: string | null;
};

let ebayTokenCache: { token: string; expiresAt: number } | null = null;

function toBase64Utf8(input: string): string {
  const bytes = new TextEncoder().encode(input);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

export async function getEbayAccessToken(): Promise<string> {
  if (ebayTokenCache && Date.now() < ebayTokenCache.expiresAt) {
    return ebayTokenCache.token;
  }
  const clientId = Deno.env.get('EBAY_CLIENT_ID');
  const clientSecret = Deno.env.get('EBAY_CLIENT_SECRET');
  if (!clientId || !clientSecret) {
    throw new Error('Missing EBAY_CLIENT_ID or EBAY_CLIENT_SECRET');
  }
  const basicAuth = toBase64Utf8(`${clientId}:${clientSecret}`);
  const res = await fetch(EBAY_IDENTITY_URL, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${basicAuth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials&scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope',
  });
  if (!res.ok) throw new Error(`ebay oauth ${res.status}: ${await res.text()}`);
  const data = await res.json();
  const token = String(data.access_token ?? '');
  const expiresIn = Number(data.expires_in ?? 7200);
  if (!token) throw new Error('ebay oauth token missing');
  ebayTokenCache = {
    token,
    expiresAt: Date.now() + Math.max(expiresIn - 120, 300) * 1000,
  };
  return token;
}

function buyingOptionsTokens(buyingOptions: unknown): string[] {
  if (!Array.isArray(buyingOptions)) {
    const s = String(buyingOptions ?? '').trim();
    return s ? [s] : [];
  }
  return buyingOptions.map((o) => String(o ?? '').trim()).filter(Boolean);
}

/** Honors full eBay `buyingOptions` array (e.g. `AUCTION` + `BEST_OFFER`). */
function listingTypeFromBuyingOptions(
  buyingOptions: unknown,
): 'AUCTION' | 'FIXED_PRICE' | 'BEST_OFFER' {
  const opts = buyingOptionsTokens(buyingOptions).map((o) => o.toUpperCase());
  const hasBestOffer = opts.some((o) => o === 'BEST_OFFER' || o.includes('BEST_OFFER'));
  const hasAuction = opts.some((o) => o === 'AUCTION' || o.includes('AUCTION'));
  if (hasBestOffer) return 'BEST_OFFER';
  if (hasAuction) return 'AUCTION';
  return 'FIXED_PRICE';
}

function readBrowseItemEndDate(raw: unknown): string | null {
  if (typeof raw === 'string' && raw.trim().length > 0) return raw.trim();
  if (raw != null && typeof raw === 'object') {
    const v = (raw as { value?: unknown }).value;
    if (typeof v === 'string' && v.trim().length > 0) return v.trim();
  }
  return null;
}

/** Search active (buy-it-now / auction) listings; returns [] on failure. */
export async function fetchActiveListingsBrowse(
  query: string,
  options?: { useCategoryFilter?: boolean },
): Promise<EbayActiveListingRow[]> {
  try {
    const token = await getEbayAccessToken();
    const marketplaceId = Deno.env.get('EBAY_MARKETPLACE_ID') ?? 'EBAY_US';
    const useCategoryFilter = options?.useCategoryFilter ?? true;
    const categoryPart = useCategoryFilter ? '&category_ids=261328' : '';
    const url =
      `${EBAY_API_BASE_URL}/buy/browse/v1/item_summary/search?q=${encodeURIComponent(query)}${categoryPart}&limit=50`;
    const res = await fetch(url, {
      headers: {
        Authorization: `Bearer ${token}`,
        'X-EBAY-C-MARKETPLACE-ID': marketplaceId,
      },
    });
    if (!res.ok) {
      console.log('[ebay-browse-active] non-200 response:', {
        status: res.status,
        marketplaceId,
        useCategoryFilter,
        query,
      });
      return [];
    }
    const data = await res.json();
    const sourceItems = Array.isArray(data?.itemSummaries) ? data.itemSummaries : [];
    return sourceItems
      .map((p: any) => {
        const buyingTokens = buyingOptionsTokens(p.buyingOptions);
        return {
          ebay_item_id: p.itemId ?? null,
          title: p.title ?? '',
          price: Number.parseFloat(String(p.price?.value ?? 0)),
          buying_format_raw: buyingTokens.join(','),
          listing_type: listingTypeFromBuyingOptions(p.buyingOptions),
          url: p.itemWebUrl ?? null,
          image_url: p.image?.imageUrl ?? null,
          itemEndDate: readBrowseItemEndDate(p.itemEndDate),
        } satisfies EbayActiveListingRow;
      })
      .filter((row: EbayActiveListingRow) => row.price > 0 && row.title);
  } catch (e) {
    console.log('[ebay-browse-active] exception:', e);
    return [];
  }
}
