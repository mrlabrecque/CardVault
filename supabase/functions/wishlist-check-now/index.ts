import { createClient } from 'jsr:@supabase/supabase-js@2';

const SCRAPECHAIN_URL = 'https://ebay-api.scrapechain.com/findActiveItems';

// ── Query builder (mirrors wishlist.ts buildEbayQuery) ─────────────────────

function buildWishlistQuery(item: Record<string, any>): string {
  const parts: string[] = [];
  if (item.year)        parts.push(String(item.year));
  if (item.set_name)    parts.push(item.set_name);
  if (item.player)      parts.push(item.player);
  if (item.card_number) parts.push(`#${item.card_number}`);

  const parallelLabel = (item.parallel ?? '').replace(/\s*\/\d+$/, '').trim();
  if (parallelLabel && parallelLabel.toLowerCase() !== 'base') parts.push(parallelLabel);

  if (item.is_auto)    parts.push('Auto');
  if (item.is_patch)   parts.push('Patch');
  if (item.serial_max) parts.push(`/${item.serial_max}`);
  if (item.is_rookie)  parts.push('RC');
  if (item.grade)      parts.push(item.grade);

  const base = item.ebay_query || parts.filter(Boolean).join(' ');
  const exclusions = (item.exclude_terms ?? []).map((t: string) => `-"${t}"`).join(' ');
  return exclusions ? `${base} ${exclusions}` : base;
}

// ── Active listings fetch ──────────────────────────────────────────────────

async function fetchActiveListings(query: string): Promise<any[]> {
  try {
    const res = await fetch(SCRAPECHAIN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ keywords: query, max_search_results: 20, category_id: '261328' }),
    });
    if (!res.ok) return [];
    const data = await res.json();
    return (data.products ?? []).map((p: any) => ({
      ebay_item_id:  p.item_id ?? null,
      title:         p.title ?? '',
      price:         parseFloat(p.price ?? p.sale_price ?? '0'),
      listing_type:  (p.buying_format ?? '').toLowerCase().includes('auction') ? 'AUCTION' : 'FIXED_PRICE',
      url:           p.link ?? p.url ?? null,
      image_url:     p.image ?? p.image_url ?? null,
    })).filter((p: any) => p.price > 0);
  } catch {
    return [];
  }
}

// ── Handler ────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
      },
    });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  const supabaseUrl    = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const anonKey        = Deno.env.get('SUPABASE_ANON_KEY')!;

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Load active/paused wishlist items for this user
  const { data: items, error: fetchError } = await admin
    .from('wishlist')
    .select('*')
    .eq('user_id', user.id)
    .in('alert_status', ['active', 'triggered']);

  if (fetchError || !items) {
    return new Response(JSON.stringify({ error: 'Failed to load wishlist' }), { status: 500 });
  }

  const now = new Date().toISOString();
  let checked = 0;
  let triggered = 0;

  for (const item of items) {
    const query = buildWishlistQuery(item);
    if (!query.trim()) continue;

    checked++;
    const listings = await fetchActiveListings(query);

    // Find listings below target price
    const matches = item.target_price
      ? listings.filter((l: any) => l.price <= item.target_price)
      : [];

    const lowestPrice = matches.length > 0
      ? Math.min(...matches.map((m: any) => m.price))
      : listings.length > 0
        ? Math.min(...listings.map((l: any) => l.price))
        : null;

    const newStatus = matches.length > 0 ? 'triggered' : 'active';
    if (newStatus === 'triggered') triggered++;

    // Update wishlist item
    await admin.from('wishlist').update({
      alert_status:    newStatus,
      last_seen_price: lowestPrice,
      last_checked_at: now,
    }).eq('id', item.id);

    // Replace matches
    if (matches.length > 0) {
      await admin.from('wishlist_matches').delete().eq('wishlist_id', item.id);
      await admin.from('wishlist_matches').insert(
        matches.map((m: any) => ({
          wishlist_id:  item.id,
          ebay_item_id: m.ebay_item_id,
          title:        m.title,
          price:        m.price,
          listing_type: m.listing_type,
          url:          m.url,
          image_url:    m.image_url,
        }))
      );
    } else if (item.alert_status === 'triggered') {
      // Was triggered but no longer below target — clear old matches
      await admin.from('wishlist_matches').delete().eq('wishlist_id', item.id);
    }
  }

  return new Response(
    JSON.stringify({ checked, triggered }),
    { headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } },
  );
});
