// eBay Finding API for sold comps; Trading API for listing creation.
// Docs: developer.ebay.com → Traditional APIs → Finding API
// Auth: App ID only, no OAuth needed.
//
// We use findCompletedItems + SoldItemsOnly=true — the only eBay API that
// reliably returns sold (not active) listings without special access grants.
// The Browse API has no working filter for historical sold data.

const EBAY_FINDING_URL = 'https://svcs.ebay.com/services/search/FindingService/v1';

// Maps Finding API listingInfo to the buyingOptions shape used throughout the app.
// Auctions: final bid is the authoritative price.
// Fixed price + bestOfferEnabled: listed price may not equal the accepted offer.
function resolveBuyingOptions(listingInfo: any): string[] {
  const type: string = listingInfo?.listingType?.[0] ?? '';
  if (type === 'Auction' || type === 'AuctionWithBIN') return ['AUCTION'];
  if (listingInfo?.bestOfferEnabled?.[0] === 'true')   return ['BEST_OFFER'];
  return ['FIXED_PRICE'];
}

export async function searchSoldListings(query: string): Promise<object[]> {
  const appId = process.env.EBAY_APP_ID!;

  const params = new URLSearchParams({
    'OPERATION-NAME':                 'findCompletedItems',
    'SERVICE-VERSION':                '1.0.0',
    'SECURITY-APPNAME':               appId,
    'RESPONSE-DATA-FORMAT':           'JSON',
    'REST-PAYLOAD':                   'true',
    'keywords':                       query,
    'itemFilter(0).name':             'SoldItemsOnly',
    'itemFilter(0).value':            'true',
    'sortOrder':                      'EndTimeSoonest',
    'paginationInput.entriesPerPage': '10',
  });

  const res = await fetch(`${EBAY_FINDING_URL}?${params}`);
  const data = (await res.json()) as any;
  if (!res.ok) throw new Error(`eBay Finding API error ${res.status}: ${JSON.stringify(data)}`);

  const items: any[] =
    data?.findCompletedItemsResponse?.[0]?.searchResult?.[0]?.item ?? [];

  // Normalize to the shape the rest of the codebase expects
  return items.map((item: any) => ({
    itemId:        item.itemId?.[0],
    title:         item.title?.[0],
    price: {
      value:    item.sellingStatus?.[0]?.currentPrice?.[0]?.__value__,
      currency: item.sellingStatus?.[0]?.currentPrice?.[0]?.['@currencyId'] ?? 'USD',
    },
    buyingOptions: resolveBuyingOptions(item.listingInfo?.[0]),
    itemEndDate:   item.listingInfo?.[0]?.endTime?.[0] ?? null,
    itemWebUrl:    item.viewItemURL?.[0] ?? null,
  }));
}

export async function createListing(card: Record<string, unknown>): Promise<object> {
  // TODO: Implement eBay Trading API AddFixedPriceItem call
  console.log(`Creating eBay listing for card: ${card['id']}`);
  return { itemId: null, status: 'not_implemented' };
}
