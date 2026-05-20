import { createClient } from 'jsr:@supabase/supabase-js@2';
import { verifyUserJwt } from './supabase_user_jwt.ts';

const COMPS_URL = 'https://api.cardhedger.com/v1/cards/comps';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function toFiniteNumber(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const n = parseFloat(v.replace(/[^0-9.-]/g, ''));
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/** Mean of positive prices in `raw_prices` (same shape as `cardhedge-grade-comps`). */
function avgFromRawPrices(payload: Record<string, unknown>): { avg: number; count: number } {
  const rawPrices = payload.raw_prices;
  const prices: number[] = [];
  if (Array.isArray(rawPrices)) {
    for (const rp of rawPrices) {
      if (!rp || typeof rp !== 'object') continue;
      const o = rp as Record<string, unknown>;
      const price = typeof o.price === 'number' ? o.price : parseFloat(String(o.price ?? '0'));
      if (Number.isFinite(price) && price > 0) prices.push(price);
    }
  }
  if (prices.length === 0) {
    const cp = toFiniteNumber(payload.comp_price);
    if (cp != null && cp > 0) return { avg: cp, count: 0 };
    return { avg: 0, count: 0 };
  }
  const sum = prices.reduce((a, b) => a + b, 0);
  return { avg: sum / prices.length, count: prices.length };
}

async function fetchGuideCompsPayload(
  apiKey: string,
  guideCardId: string,
  grade: string,
): Promise<Record<string, unknown> | null> {
  const chGrade = grade.trim() === '' || grade === 'Raw' ? 'Raw' : grade;
  const res = await fetch(COMPS_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
    },
    body: JSON.stringify({
      card_id: guideCardId,
      count: 40,
      grade: chGrade,
      include_raw_prices: true,
      time_weighted: false,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    console.error('[grading-comps-sold-analyze] CardHedge comps', res.status, text.slice(0, 800));
    return null;
  }
  try {
    return await res.json() as Record<string, unknown>;
  } catch {
    return null;
  }
}

/** PSA tier sold comps summary from CardHedge guide `/v1/cards/comps` (replaces eBay scrape). */
export async function handleGradingCompsSoldAnalyze(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Unauthorized' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const userId = await verifyUserJwt(authHeader, supabaseUrl);
    if (!userId) return json({ error: 'Unauthorized' }, 401);

    const apiKey =
      Deno.env.get('CARDHEDGE_API_KEY')?.trim() ||
      Deno.env.get('CARDHEDGER_API_KEY')?.trim();
    if (!apiKey) {
      return json({ error: 'Price guide API is not configured' }, 503);
    }

    const { userCardId } = await req.json();
    if (!userCardId) return json({ error: 'userCardId is required' }, 400);

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: card, error: cardErr } = await admin
      .from('user_cards')
      .select(`
        id,
        master_card_definitions (
          cardhedge_id,
          set_cards (
            player, card_number,
            sets ( name, releases ( year, name ) )
          ),
          set_parallels!parallel_id ( name )
        )
      `)
      .eq('id', userCardId)
      .eq('user_id', userId)
      .single();

    if (cardErr || !card) return json({ error: 'Card not found' }, 404);

    let mcd = (card as Record<string, unknown>).master_card_definitions as
      | Record<string, unknown>
      | Record<string, unknown>[]
      | null;
    if (Array.isArray(mcd)) mcd = mcd[0] ?? null;
    mcd = mcd as Record<string, unknown> | null;
    const guideId = typeof mcd?.cardhedge_id === 'string' ? mcd.cardhedge_id.trim() : '';
    if (!guideId) {
      return json({
        error: 'no_cardhedge_link',
        message: 'Link this card to the price guide before sold comps analysis.',
        rawQuery: '',
        psa9: { avg: 0, count: 0, query: '' },
        psa10: { avg: 0, count: 0, query: '' },
      }, 400);
    }

    let sc = mcd?.set_cards as Record<string, unknown> | Record<string, unknown>[] | null;
    if (Array.isArray(sc)) sc = sc[0] ?? null;
    let sets = sc?.sets as Record<string, unknown> | Record<string, unknown>[] | null;
    if (Array.isArray(sets)) sets = sets[0] ?? null;
    let rel = sets?.releases as Record<string, unknown> | Record<string, unknown>[] | null;
    if (Array.isArray(rel)) rel = rel[0] ?? null;
    const sp = mcd?.set_parallels as Record<string, unknown> | Record<string, unknown>[] | undefined;
    const spRow = Array.isArray(sp) ? sp[0] as Record<string, unknown> | undefined : sp as Record<string, unknown> | undefined;
    const parallel = typeof spRow?.name === 'string' && spRow.name.trim().length > 0 ? spRow.name.trim() : 'Base';

    const parts = [
      rel?.year != null ? String(rel.year) : '',
      typeof rel?.name === 'string' ? rel.name : '',
      typeof sets?.name === 'string' ? sets.name : '',
      typeof sc?.player === 'string' ? sc.player : '',
      sc?.card_number != null ? `#${sc.card_number}` : '',
      parallel.toLowerCase() !== 'base' ? parallel : '',
    ].filter((p) => p.length > 0);
    const rawQuery = parts.join(' ');

    const psa9Payload = await fetchGuideCompsPayload(apiKey, guideId, 'PSA 9');
    await new Promise((r) => setTimeout(r, 250));
    const psa10Payload = await fetchGuideCompsPayload(apiKey, guideId, 'PSA 10');

    const psa9Stats = psa9Payload ? avgFromRawPrices(psa9Payload) : { avg: 0, count: 0 };
    const psa10Stats = psa10Payload ? avgFromRawPrices(psa10Payload) : { avg: 0, count: 0 };

    return json({
      rawQuery,
      psa9: { avg: psa9Stats.avg, count: psa9Stats.count, query: `CardHedge comps PSA 9 (${guideId})` },
      psa10: { avg: psa10Stats.avg, count: psa10Stats.count, query: `CardHedge comps PSA 10 (${guideId})` },
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[grading-comps-sold-analyze]', msg);
    return json({ error: 'Internal server error', detail: msg }, 500);
  }
}
