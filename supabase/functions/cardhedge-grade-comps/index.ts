/**
 * Fetches sold comps for a CardHedge card + grade (POST /v1/cards/comps),
 * upserts `comps_cache`, replaces existing rows for that catalog variant + grade,
 * and stores `sale_type` from the API payload. `parallel_name` on rows is taken
 * from `master_card_definitions.parallel_id` → `set_parallels`.
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { verifyUserJwt } from '../_shared/supabase_user_jwt.ts';

const COMPS_URL = 'https://api.cardhedger.com/v1/cards/comps';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function mapSaleType(raw: unknown): 'auction' | 'fixed_price' | 'best_offer' {
  const s = typeof raw === 'string' ? raw.toLowerCase() : '';
  if (s.includes('auction')) return 'auction';
  if (s.includes('best offer') || s.includes('best_offer')) return 'best_offer';
  return 'fixed_price';
}

function normalizeGrade(g: string): string {
  const t = g.trim();
  if (!t) return 'Raw';
  return t;
}

function extractEbayItemId(saleUrl: string | null): string | null {
  if (!saleUrl) return null;
  const m = saleUrl.match(/\/itm\/(\d{6,})/i);
  return m?.[1] ?? null;
}

function normalizePriceSource(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const t = v.trim().toLowerCase();
  return t.length > 0 ? t : null;
}

function parallelNameFromMaster(master: Record<string, unknown>): string {
  const sp = master.set_parallels as Record<string, unknown> | Record<string, unknown>[] | null | undefined;
  if (!sp) return 'Base';
  const row = Array.isArray(sp) ? (sp[0] as Record<string, unknown> | undefined) : (sp as Record<string, unknown>);
  const n = typeof row?.name === 'string' ? row.name.trim() : '';
  return n.length > 0 ? n : 'Base';
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS, status: 200 });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Unauthorized' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const userId = await verifyUserJwt(authHeader, supabaseUrl);
  if (!userId) return json({ error: 'Unauthorized' }, 401);

  const apiKey =
    Deno.env.get('CARDHEDGE_API_KEY')?.trim() ||
    Deno.env.get('CARDHEDGER_API_KEY')?.trim();
  if (!apiKey) {
    return json({ error: 'CardHedge is not configured' }, 503);
  }

  let body: {
    masterVariantId?: string;
    cardhedgeId?: string;
    grade?: string;
    count?: number;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const masterVariantId = body.masterVariantId?.trim();
  const cardhedgeId = body.cardhedgeId?.trim();
  const grade = normalizeGrade(body.grade ?? 'Raw');
  const count = Math.min(100, Math.max(1, Math.trunc(Number(body.count) || 40)));

  if (!masterVariantId) return json({ error: 'masterVariantId required' }, 400);
  if (!cardhedgeId) return json({ error: 'cardhedgeId required' }, 400);

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: row, error: qErr } = await admin
    .from('master_card_definitions')
    .select(`
      id,
      set_parallels!parallel_id ( name )
    `)
    .eq('id', masterVariantId)
    .maybeSingle();
  if (qErr || !row) return json({ error: 'Variant not found' }, 404);

  const catalogParallel = parallelNameFromMaster(row as Record<string, unknown>);

  const chGrade = grade === 'Raw' ? 'Raw' : grade;

  const upstream = await fetch(COMPS_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
    },
    body: JSON.stringify({
      card_id: cardhedgeId,
      count,
      grade: chGrade,
      include_raw_prices: true,
      time_weighted: false,
    }),
  });

  if (!upstream.ok) {
    const text = await upstream.text();
    console.error('[cardhedge-grade-comps] upstream', upstream.status, text.slice(0, 2000));
    return json(
      { error: 'CardHedge comps request failed', status: upstream.status, details: text.slice(0, 500) },
      502,
    );
  }

  let payload: Record<string, unknown>;
  try {
    payload = await upstream.json() as Record<string, unknown>;
  } catch {
    return json({ error: 'Invalid JSON from CardHedge' }, 502);
  }

  const rawPrices = payload.raw_prices;
  const items: Record<string, unknown>[] = [];
  if (Array.isArray(rawPrices)) {
    for (const rp of rawPrices) {
      if (!rp || typeof rp !== 'object') continue;
      const o = rp as Record<string, unknown>;
      const price = typeof o.price === 'number' ? o.price : parseFloat(String(o.price ?? '0'));
      if (!Number.isFinite(price) || price <= 0) continue;
      const title = String(o.title ?? 'Sale');
      const saleUrl = typeof o.sale_url === 'string' ? o.sale_url : null;
      const img = typeof o.image === 'string' ? o.image : null;
      const soldAt = typeof o.sale_date === 'string' ? o.sale_date : null;
      const phId = typeof o.price_history_id === 'string' ? o.price_history_id : null;
      const priceSource = normalizePriceSource(o.price_source) ?? 'ebay';
      const ebayItem = extractEbayItemId(saleUrl) ?? phId;
      items.push({
        title,
        price,
        currency: 'USD',
        sale_type: mapSaleType(o.sale_type),
        sold_at: soldAt,
        url: saleUrl,
        image_url: img,
        grade,
        price_source: priceSource,
        raw_sale_type: typeof o.sale_type === 'string' ? o.sale_type : null,
        ebay_item_id: ebayItem,
        price_history_id: phId,
      });
    }
  }

  const cacheKey = `cardhedge:${cardhedgeId}:${masterVariantId}:${grade}`;
  const now = new Date().toISOString();
  await admin.from('comps_cache').upsert({
    query: cacheKey,
    items,
    fetched_at: now,
  }, { onConflict: 'query' });

  await admin
    .from('card_sold_comps')
    .delete()
    .eq('master_card_id', masterVariantId)
    .eq('grade', grade);

  if (items.length > 0) {
    const rows = items.map((it) => ({
      master_card_id: masterVariantId,
      parallel_name: catalogParallel,
      grade: it.grade as string,
      ebay_item_id: (it.ebay_item_id as string | null) ?? null,
      title: it.title as string,
      price: it.price as number,
      currency: 'USD',
      sale_type: it.sale_type as string,
      sold_at: it.sold_at as string | null,
      url: it.url as string | null,
      image_url: it.image_url as string | null,
      fetched_at: now,
    }));
    const { error: insErr } = await admin.from('card_sold_comps').insert(rows);
    if (insErr) {
      console.error('[cardhedge-grade-comps] insert', insErr);
      return json({ error: 'Failed to save comps', details: insErr.message }, 500);
    }
  }

  return json({
    ok: true,
    count: items.length,
    cache_key: cacheKey,
    comp_price: payload.comp_price ?? null,
    count_used: payload.count_used ?? null,
  });
});
