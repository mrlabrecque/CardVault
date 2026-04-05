// eBay Browse API for sold comps; Trading API for listing creation
// Docs: https://developer.ebay.com/develop/apis

const EBAY_TOKEN_URL = 'https://api.ebay.com/identity/v1/oauth2/token';
const EBAY_BROWSE_URL = 'https://api.ebay.com/buy/browse/v1/item_summary/search';

let tokenCache: { token: string; expiresAt: number } | null = null;

async function getAppToken(): Promise<string> {
  if (tokenCache && Date.now() < tokenCache.expiresAt) {
    return tokenCache.token;
  }

  const appId = process.env.EBAY_APP_ID!;
  const certId = process.env.EBAY_CERT_ID!;
  const credentials = Buffer.from(`${appId}:${certId}`).toString('base64');

  const res = await fetch(EBAY_TOKEN_URL, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${credentials}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials&scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope',
  });

  const data = (await res.json()) as any;
  if (!data.access_token) throw new Error(`eBay token error: ${JSON.stringify(data)}`);

  tokenCache = {
    token: data.access_token,
    expiresAt: Date.now() + (data.expires_in - 60) * 1000,
  };
  return tokenCache.token;
}

export async function searchSoldListings(query: string): Promise<object[]> {
  const token = await getAppToken();

  const params = new URLSearchParams({
    q: query,
    filter: 'soldItems:{true}',
    limit: '10',
  });

  const res = await fetch(`${EBAY_BROWSE_URL}?${params}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US',
      'Content-Type': 'application/json',
    },
  });

  const data = (await res.json()) as any;
  if (!res.ok) throw new Error(`eBay Browse error ${res.status}: ${JSON.stringify(data)}`);
  return data.itemSummaries ?? [];
}

export async function createListing(card: Record<string, unknown>): Promise<object> {
  // TODO: Implement eBay Trading API AddFixedPriceItem call
  console.log(`Creating eBay listing for card: ${card['id']}`);
  return { itemId: null, status: 'not_implemented' };
}
