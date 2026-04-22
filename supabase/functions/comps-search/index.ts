import { createClient } from 'jsr:@supabase/supabase-js@2';

const SCRAPECHAIN_URL = 'https://ebay-api.scrapechain.com/findCompletedItems';
const LOOKBACK_DAYS = 90;
const MAX_RETRIES = 3;
const RETRY_BASE_MS = 2000;
const HISTORY_LIMIT = 50;

const USER_AGENTS = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
];

function resolveSaleType(buying_format: string | null): string {
  const fmt = (buying_format ?? '').toLowerCase();
  if (fmt.includes('auction')) return 'auction';
  if (fmt.includes('best offer') || fmt.includes('best_offer')) return 'best_offer';
  return 'fixed_price';
}

async function fetchSoldListings(query: string): Promise<any[]> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - LOOKBACK_DAYS);

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const agent = USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)];
      const res = await fetch(SCRAPECHAIN_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'User-Agent': agent },
        body: JSON.stringify({ keywords: query, max_search_results: 120, remove_outliers: false, category_id: '261328' }),
      });
      if (!res.ok) throw new Error(`scrapechain ${res.status}: ${await res.text()}`);
      const data = await res.json();

      return (data.products ?? [])
        .map((p: any) => ({
          itemId:        p.item_id ?? null,
          title:         p.title ?? '',
          price:         parseFloat(p.sale_price ?? 0),
          currency:      p.currency ?? 'USD',
          sale_type:     resolveSaleType(p.buying_format),
          sold_at:       p.date_sold ?? null,
          url:           p.link ?? null,
        }))
        .filter((item: any) => !item.sold_at || new Date(item.sold_at) >= cutoff);
    } catch (e: any) {
      if (attempt === MAX_RETRIES) throw e;
      await new Promise(r => setTimeout(r, RETRY_BASE_MS * Math.pow(2, attempt - 1)));
    }
  }
  return [];
}

// Drop lot listings only — eBay's keyword match is already good for free-text search.
function filterResults(items: any[]): any[] {
  return items.filter(item => !/\blot\b/i.test(item.title ?? ''));
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function b64urlToBytes(b64url: string): Uint8Array {
  const b64 = b64url.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0));
}

function b64urlToJson(b64url: string): any {
  return JSON.parse(new TextDecoder().decode(b64urlToBytes(b64url)));
}

let cachedJwks: any[] | null = null;

async function getJwks(supabaseUrl: string): Promise<any[]> {
  if (cachedJwks) return cachedJwks;
  const res = await fetch(`${supabaseUrl}/auth/v1/.well-known/jwks.json`);
  const data = await res.json();
  cachedJwks = data.keys ?? [];
  return cachedJwks!;
}

async function verifyJwt(token: string, supabaseUrl: string): Promise<string | null> {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const header  = b64urlToJson(parts[0]);
    const payload = b64urlToJson(parts[1]);

    const jwks = await getJwks(supabaseUrl);
    const jwk  = jwks.find((k: any) => k.kid === header.kid) ?? jwks[0];
    if (!jwk) return null;

    const key = await crypto.subtle.importKey(
      'jwk', jwk,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false, ['verify'],
    );
    const valid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      key,
      b64urlToBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
    if (!valid) return null;
    return payload?.sub ?? null;
  } catch (e) {
    console.error('verifyJwt error:', e);
    return null;
  }
}

Deno.serve(async (req) => {
  console.log('comps-search called:', req.method);
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Unauthorized' }, 401);

    const supabaseUrl    = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const token = authHeader.replace(/^Bearer\s+/i, '');
    const userId = await verifyJwt(token, supabaseUrl);
    console.log('userId:', userId);
    if (!userId) return json({ error: 'Unauthorized' }, 401);

    const { query } = await req.json();
    console.log('query:', query);
    if (!query) return json({ error: 'query is required' }, 400);

  let raw: any[];
  try {
    raw = await fetchSoldListings(query);
  } catch (e: any) {
    return json({ error: `Scrapechain error: ${e.message}` }, 502);
  }

  const items = filterResults(raw);

  const prices = items.map(i => i.price).filter(p => p > 0);
  const avgPrice = prices.length > 0
    ? prices.reduce((s, p) => s + p, 0) / prices.length
    : null;

  const admin = createClient(supabaseUrl, serviceRoleKey);

  const { data: existing } = await admin
    .from('lookup_history')
    .select('id')
    .eq('user_id', userId)
    .ilike('query', query)
    .limit(1)
    .single();

  if (!existing) {
    const { count } = await admin
      .from('lookup_history')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)
      .then(r => ({ count: r.count ?? 0 }));

    if (count >= HISTORY_LIMIT) {
      const { data: oldest } = await admin
        .from('lookup_history')
        .select('id')
        .eq('user_id', userId)
        .order('timestamp', { ascending: true })
        .limit(1)
        .single();
      if (oldest) await admin.from('lookup_history').delete().eq('id', oldest.id);
    }

    await admin.from('lookup_history').insert({
      user_id:   userId,
      query,
      results:   items,
      timestamp: new Date().toISOString(),
    });
  }

    return json({ items, avgPrice });
  } catch (e: any) {
    console.error('unhandled error:', e?.message ?? e);
    return json({ error: 'Internal server error', detail: e?.message }, 500);
  }
});
