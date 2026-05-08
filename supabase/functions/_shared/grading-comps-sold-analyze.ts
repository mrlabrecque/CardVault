import { createClient } from 'jsr:@supabase/supabase-js@2';
import { fetchSoldListingsScrapingBee, soldRefreshRowsToSearchShape } from './sold_listings_sgai.ts';
const MAX_RETRIES = 2;
const RETRY_BASE_MS = 2000;

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
    const header = b64urlToJson(parts[0]);
    const payload = b64urlToJson(parts[1]);
    const jwks = await getJwks(supabaseUrl);
    const jwk = jwks.find((k: any) => k.kid === header.kid) ?? jwks[0];
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

function buildCardEbayQuery(card: any): string {
  const { year, release_name, set_name, player, card_number, parallel_type, is_auto, is_patch, is_rookie, serial_max } = card;

  const parts: string[] = [String(year ?? ''), release_name ?? ''];

  const setLabel = (set_name ?? '').trim();
  if (
    setLabel &&
    setLabel.toLowerCase() !== 'base' &&
    !(release_name ?? '').toLowerCase().includes(setLabel.toLowerCase())
  ) {
    parts.push(setLabel);
  }

  parts.push(player ?? '');
  if (card_number) parts.push(`#${card_number}`);

  const parallelLabel = (parallel_type ?? '').replace(/\s*\/\d+$/, '').trim();
  const attrs: string[] = [];
  if (parallelLabel && parallelLabel !== 'Base') attrs.push(parallelLabel);
  if (is_auto) attrs.push('Auto');
  if (is_patch) attrs.push('Patch');
  if (serial_max) attrs.push(`/${serial_max}`);
  if (is_rookie) attrs.push('RC');

  return [...parts, ...attrs].filter(Boolean).join(' ');
}

async function fetchSoldListings(query: string): Promise<any[]> {
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const rows = await fetchSoldListingsScrapingBee(query);
      return soldRefreshRowsToSearchShape(rows)
        .map((p: any) => ({ ...p, url: p.url ?? null }))
        .filter((p: any) => p.title && p.price > 0);
    } catch (e: any) {
      if (attempt === MAX_RETRIES) throw e;
      await new Promise(r => setTimeout(r, RETRY_BASE_MS * attempt));
    }
  }
  return [];
}

function filterGradedItems(items: any[], grader: string, grade: string): any[] {
  return items.filter(item => {
    const title = (item.title ?? '').toLowerCase();
    if (item.price <= 0) return false;
    if (/\blot\b/i.test(title)) return false;
    if (!new RegExp(`\\b${grader}\\b`, 'i').test(title)) return false;
    if (!new RegExp(`\\b${grade}\\b`).test(title)) return false;
    if (grade === '9' && /\bpsa\s*10\b/i.test(title)) return false;
    if (grade === '10' && /\bpsa\s*9\b/i.test(title)) return false;
    return true;
  });
}

function avgPrice(items: any[]): number {
  const prices = items.map((i: any) => i.price).filter((p: number) => p > 0);
  if (!prices.length) return 0;
  return prices.reduce((s: number, p: number) => s + p, 0) / prices.length;
}

/** Sold comps PSA tier analysis — shared by `grading-analyze` (legacy) and `grading-comps-sold-analyze`. */
export async function handleGradingCompsSoldAnalyze(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Unauthorized' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const token = authHeader.replace(/^Bearer\s+/i, '');
    const userId = await verifyJwt(token, supabaseUrl);
    if (!userId) return json({ error: 'Unauthorized' }, 401);

    const { userCardId } = await req.json();
    if (!userCardId) return json({ error: 'userCardId is required' }, 400);

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: card, error: cardErr } = await admin
      .from('user_cards')
      .select(`
        id,
        price_paid,
        parallel_name,
        master_card_definitions (
          player, card_number, is_rookie, is_auto, is_patch, serial_max,
          sets ( name, releases ( year, sport, name ) )
        )
      `)
      .eq('id', userCardId)
      .eq('user_id', userId)
      .single();

    if (cardErr || !card) return json({ error: 'Card not found' }, 404);

    const mcd = (card as any).master_card_definitions ?? {};
    const setData = mcd.sets ?? {};
    const release = setData.releases ?? {};

    const normalized = {
      year: release.year ?? null,
      release_name: release.name ?? '',
      set_name: setData.name ?? '',
      player: mcd.player ?? '',
      card_number: mcd.card_number ?? null,
      parallel_type: (card as any).parallel_name ?? 'Base',
      is_auto: mcd.is_auto ?? false,
      is_patch: mcd.is_patch ?? false,
      is_rookie: mcd.is_rookie ?? false,
      serial_max: mcd.serial_max ?? null,
    };

    const rawQuery = buildCardEbayQuery(normalized);
    const psa9Query = `${rawQuery} PSA 9`;
    const psa10Query = `${rawQuery} PSA 10`;
    const gemMintQuery = `${rawQuery} Graded 10 Gem Mint`;

    console.log('grading-comps-sold-analyze queries:', { psa9Query, psa10Query });

    const psa9Raw = await fetchSoldListings(psa9Query);
    await new Promise(r => setTimeout(r, 500));
    const psa10Raw = await fetchSoldListings(psa10Query);
    await new Promise(r => setTimeout(r, 500));
    const gemMintRaw = await fetchSoldListings(gemMintQuery);

    const psa9Items = filterGradedItems(psa9Raw, 'psa', '9');

    const psa10Filtered = filterGradedItems(psa10Raw, 'psa', '10');
    const gemMintFiltered = filterGradedItems(gemMintRaw, 'psa', '10');
    const seen = new Set(psa10Filtered.map((i: any) => i.itemId).filter(Boolean));
    const merged = [...psa10Filtered, ...gemMintFiltered.filter((i: any) => !seen.has(i.itemId))];

    return json({
      rawQuery,
      psa9: { avg: avgPrice(psa9Items), count: psa9Items.length, query: psa9Query },
      psa10: { avg: avgPrice(merged), count: merged.length, query: psa10Query },
    });
  } catch (e: any) {
    console.error('[grading-comps-sold-analyze]', e?.message ?? e);
    return json({ error: 'Internal server error', detail: e?.message }, 500);
  }
}
