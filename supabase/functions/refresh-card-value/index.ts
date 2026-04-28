import { createClient } from 'jsr:@supabase/supabase-js@2';

const SCRAPECHAIN_URL = 'https://ebay-api.scrapechain.com/findCompletedItems';
const LOOKBACK_DAYS = 90;
const MAX_RETRIES = 3;
const RETRY_BASE_MS = 2000;

const USER_AGENTS = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
];

// ── Filtering constants (ported from comps.service.ts) ─────────────────────

const PARALLEL_KEYWORDS = [
  'refractor', 'holo', 'silver', 'gold', 'red', 'blue', 'green', 'orange',
  'purple', 'pink', 'black', 'white', 'teal', 'yellow', 'brown', 'gray', 'grey',
  'hyper', 'neon', 'aqua', 'mojo', 'wave', 'velocity', 'stars', 'scope',
  'cracked ice', 'disco', 'tiger', 'nebula', 'shimmer', 'choice', 'lava',
  'sp', 'ssp', 'foil', 'logo',
];

const GRADER_KEYWORDS = ['psa', 'bgs', 'sgc', 'cgc', 'csg', 'beckett'];

const LISTING_NOISE = new Set([
  'rookie', 'rated', 'serial', 'numbered', 'graded', 'limited', 'edition',
  'insert', 'parallel', 'short', 'print', 'chrome', 'refractor', 'invest',
  'basketball', 'football', 'baseball', 'hockey', 'soccer',
  'auction', 'auctions', 'ended', 'listing',
  'panini', 'topps', 'donruss', 'fleer', 'score', 'ultra', 'select', 'optic',
  'mosaic', 'chronicles', 'certified', 'absolute', 'contenders', 'playoff',
  'treasures', 'prestige', 'bowman', 'stadium', 'heritage', 'update', 'series',
  'national', 'upper', 'deck', 'prizm', 'trading', 'sports', 'card', 'cards',
  'single', 'color', 'colour',
]);

// ── Query builder ──────────────────────────────────────────────────────────

function buildCardEbayQuery(card: Record<string, unknown>): string {
  const {
    year, release_name, set_name, player, card_number,
    parallel_type, is_auto, is_patch, is_rookie, serial_max,
    is_graded, grader, grade_value,
  } = card as Record<string, any>;

  const parts: string[] = [String(year ?? ''), release_name ?? ''];

  const setLabel = (set_name ?? '').trim();
  if (setLabel && setLabel.toLowerCase() !== 'base' &&
      !(release_name ?? '').toLowerCase().includes(setLabel.toLowerCase())) {
    parts.push(setLabel);
  }

  parts.push(player ?? '');
  if (card_number) parts.push(`#${card_number}`);

  const parallelLabel = (parallel_type ?? '').replace(/\s*\/\d+$/, '').trim();
  const attrs: string[] = [];
  if (parallelLabel && parallelLabel !== 'Base') attrs.push(parallelLabel);
  if (is_auto)    attrs.push('Auto');
  if (is_patch)   attrs.push('Patch');
  if (serial_max) attrs.push(`/${serial_max}`);
  if (is_rookie)  attrs.push('RC');
  if (is_graded && grader && grade_value) attrs.push(`${grader} ${grade_value}`);

  return [...parts, ...attrs].filter(Boolean).join(' ');
}

// ── Filtering ──────────────────────────────────────────────────────────────

function noUnexpectedParallels(title: string, query: string): boolean {
  const t = title.toLowerCase();
  const q = query.toLowerCase();
  return !PARALLEL_KEYWORDS.some(k => {
    const re = new RegExp(`\\b${k.replace(/\s+/g, '\\s+')}\\b`);
    return re.test(t) && !q.includes(k);
  });
}

function noUnexpectedWords(title: string, query: string): boolean {
  const t = title.toLowerCase();
  const q = query.toLowerCase();
  const titleWords = t.match(/\b[a-z]{6,}\b/g) ?? [];
  return titleWords.every((word: string) => q.includes(word) || LISTING_NOISE.has(word));
}

function parseAndFilter(raw: any[], query: string, setName?: string): any[] {
  const yearMatch    = query.match(/\b(19|20)\d{2}\b/);
  const cardNumMatch = query.match(/(?:^|\s)#?(\d{1,4})(?:\s|$)/);
  const serialMatch  = query.match(/\/(\d{1,4})\b/);
  const graderFound  = GRADER_KEYWORDS.find(k => new RegExp(`\\b${k}\\b`, 'i').test(query));

  const parallelsInQuery = PARALLEL_KEYWORDS.filter(k => new RegExp(`\\b${k}\\b`, 'i').test(query));
  const parallelFromQuery = parallelsInQuery.length ? parallelsInQuery.join(' ') : null;

  const noisePattern = new RegExp(`\\b(${[...LISTING_NOISE].join('|')})\\b`, 'gi');
  const playerGuess = query
    .replace(/\b(19|20)\d{2}\b/, '')
    .replace(/(?:^|\s)#?\d{1,4}(?:\s|$)/, ' ')
    .replace(/\/\d{1,4}\b/, '')
    .replace(setName ? new RegExp(setName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+'), 'gi') : /(?:)/, '')
    .replace(new RegExp(`\\b(${PARALLEL_KEYWORDS.join('|')})\\b`, 'gi'), '')
    .replace(new RegExp(`\\b(${GRADER_KEYWORDS.join('|')})\\b`, 'gi'), '')
    .replace(/\b(rc|rookie|auto(graph)?|patch|relic|jersey)\b/gi, '')
    .replace(noisePattern, '')
    .replace(/\s{2,}/g, ' ').trim();

  const year       = yearMatch ? parseInt(yearMatch[0]) : null;
  const serial_max = serialMatch ? parseInt(serialMatch[1]) : null;
  const playerWords = playerGuess.toLowerCase().split(/\s+/).filter(Boolean);
  const parallelStr = parallelFromQuery ?? '';
  const is_auto    = /\bauto(graph)?\b/i.test(query);
  const is_patch   = /\b(patch|relic|jersey)\b/i.test(query);
  const is_graded  = !!graderFound;
  const grader     = graderFound ?? null;

  return raw.filter(item => {
    const title = (item.title ?? '').toLowerCase();
    if (playerWords.length && playerWords.some((w: string) => !title.includes(w))) return false;
    if (year && !title.includes(String(year))) return false;
    if (cardNumMatch && !new RegExp(`\\b${cardNumMatch[1]}\\b`).test(title)) return false;
    if (/\blot\b/i.test(title)) return false;
    const hasSerial = /\/\d{1,4}\b/.test(title);
    if (!serial_max && hasSerial) return false;
    if (serial_max && !new RegExp(`\\/${serial_max}\\b`).test(title)) return false;
    if (is_graded && grader && !title.includes(grader)) return false;
    const hasGrader = GRADER_KEYWORDS.some(k => new RegExp(`\\b${k}\\b`, 'i').test(title));
    if (!is_graded && hasGrader) return false;
    const hasAuto  = /\bauto(graph)?\b/.test(title);
    const hasPatch = /\b(patch|relic|mem(orabilia)?|jersey)\b/.test(title);
    if (is_auto  && !hasAuto)  return false;
    if (!is_auto  && hasAuto)  return false;
    if (is_patch && !hasPatch) return false;
    if (!is_patch && hasPatch) return false;
    if (/\bssp\b/i.test(title) && !/\bssp\b/i.test(query)) return false;
    if (/\bvariation\b/i.test(title) && !/\bvariation\b/i.test(query)) return false;
    if (parallelStr) {
      const parallelWords = parallelStr.toLowerCase().split(/\s+/).filter(Boolean);
      if (parallelWords.some((w: string) => !title.includes(w))) return false;
    }
    if (!noUnexpectedParallels(item.title, query)) return false;
    if (!noUnexpectedWords(item.title, query)) return false;
    return true;
  });
}

function resolveSaleType(buying_format: string | null): string {
  const fmt = (buying_format ?? '').toLowerCase();
  if (fmt.includes('auction')) return 'auction';
  if (fmt.includes('best offer') || fmt.includes('best_offer')) return 'best_offer';
  return 'fixed_price';
}

// ── Scrapechain fetch ──────────────────────────────────────────────────────

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
          price:         { value: String(p.sale_price ?? 0), currency: p.currency ?? 'USD' },
          buyingOptions: resolveSaleType(p.buying_format),
          itemEndDate:   p.date_sold ?? null,
          itemWebUrl:    p.link ?? null,
        }))
        .filter((item: any) => !item.itemEndDate || new Date(item.itemEndDate) >= cutoff);
    } catch (e: any) {
      if (attempt === MAX_RETRIES) throw e;
      await new Promise(r => setTimeout(r, RETRY_BASE_MS * Math.pow(2, attempt - 1)));
    }
  }
  return [];
}

// ── Handler ────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' } });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });

  const supabaseUrl    = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const anonKey        = Deno.env.get('SUPABASE_ANON_KEY')!;

  // Verify caller is authenticated
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
        'jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify'],
      );
      const valid = await crypto.subtle.verify(
        { name: 'ECDSA', hash: 'SHA-256' }, key,
        b64urlToBytes(parts[2]),
        new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
      );
      if (!valid) return null;
      return payload?.sub ?? null;
    } catch { return null; }
  }

  const supabaseUrl2 = Deno.env.get('SUPABASE_URL')!;
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const userId = await verifyJwt(token, supabaseUrl2);
  if (!userId) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });

  const { cardId } = await req.json();
  if (!cardId) return new Response(JSON.stringify({ error: 'cardId required' }), { status: 400, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });

  // Use service role for DB writes
  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Fetch the card row with all joined data
  const { data: card, error: cardError } = await admin
    .from('user_cards')
    .select(`
      id, is_graded, grader, grade_value, parallel_name,
      master_card_definitions ( id, player, card_number, is_rookie, is_auto, is_patch, serial_max,
        sets ( name, releases ( year, name, sport ) )
      )
    `)
    .eq('id', cardId)
    .eq('user_id', userId)
    .single();

  if (cardError || !card) {
    return new Response(JSON.stringify({ error: 'Card not found' }), { status: 404, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
  }

  const mcd     = (card as any).master_card_definitions ?? {};
  const masterCardId = mcd.id;
  const parallelName = (card as any).parallel_name ?? 'Base';

  if (!masterCardId) {
    return new Response(JSON.stringify({ error: 'Master card not found' }), { status: 404, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
  }

  // Delegate to get-card-comps logic via edge function invoke
  // (reuse the same implementation instead of duplicating)
  const getCardCompsRes = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/get-card-comps`, {
    method: 'POST',
    headers: {
      'Authorization': authHeader,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ masterCardId, parallelName }),
  });

  if (!getCardCompsRes.ok) {
    const error = await getCardCompsRes.text();
    return new Response(JSON.stringify({ error: `get-card-comps failed: ${error}` }), { status: getCardCompsRes.status, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
  }

  const result = await getCardCompsRes.json();

  return new Response(
    JSON.stringify(result),
    { headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } },
  );
});
