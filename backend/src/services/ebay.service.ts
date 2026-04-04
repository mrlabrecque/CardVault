// eBay Browse API for sold comps; Trading API for listing creation
// Docs: https://developer.ebay.com/develop/apis

export async function searchSoldListings(query: string): Promise<object[]> {
  // TODO: Implement eBay Browse API call with FILTER:soldItems
  console.log(`Searching eBay sold listings for: ${query}`);
  return [];
}

export async function createListing(card: Record<string, unknown>): Promise<object> {
  // TODO: Implement eBay Trading API AddFixedPriceItem call
  console.log(`Creating eBay listing for card: ${card['id']}`);
  return { itemId: null, status: 'not_implemented' };
}
