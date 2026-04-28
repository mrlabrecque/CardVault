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

// ── Filtering constants ─────────────────────────────────────────────────────

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

// ── Parallel filtering with DB-driven list ─────────────────────────────────

function buildParallelExclusionList(selectedParallelName: string, allParallelNames: string[]): Set<string> {
  if (selectedParallelName === 'Base') {
    // Base: reject any card with ANY known parallel name
    return new Set(allParallelNames.filter(p => p !== 'Base'));
  }
  // Named parallel: reject cards with OTHER parallel names
  return new Set(allParallelNames.filter(p => p !== 'Base' && p !== selectedParallelName));
}

function titleHasExcludedParallel(title: string, exclusionList: Set<string>): boolean {
  if (exclusionList.size === 0) return false;
  const t = title.toLowerCase();
  for (const parallel of exclusionList) {
    const re = new RegExp(`\\b${parallel.replace(/\s+/g, '\\s+').toLowerCase()}\\b`, 'i');
    if (re.test(t)) return true;
  }
  return false;
}

// ── Filtering ──────────────────────────────────────────────────────────────

function noUnexpectedWords(title: string, query: string): boolean {
  const t = title.toLowerCase();
  const q = query.toLowerCase();
  const titleWords = t.match(/\b[a-z]{6,}\b/g) ?? [];
  return titleWords.every((word: string) => q.includes(word) || LISTING_NOISE.has(word));
}

function parseAndFilter(
  raw: any[],
  query: string,
  selectedParallelName: string,
  allParallelNames: string[],
  setName?: string,
): any[] {
  const yearMatch    = query.match(/\b(19|20)\d{2}\b/);
  const cardNumMatch = query.match(/(?:^|\s)#?(\d{1,4})(?:\s|$)/);
  const serialMatch  = query.match(/\/(\d{1,4})\b/);

  const noisePattern = new RegExp(`\\b(${[...LISTING_NOISE].join('|')})\\b`, 'gi');
  const playerGuess = query
    .replace(/\b(19|20)\d{2}\b/, '')
    .replace(/(?:^|\s)#?\d{1,4}(?:\s|$)/, ' ')
    .replace(/\/\d{1,4}\b/, '')
    .replace(setName ? new RegExp(setName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+'), 'gi') : /(?:)/, '')
    .replace(/\b(rc|rookie|auto(graph)?|patch|relic|jersey)\b/gi, '')
    .replace(noisePattern, '')
    .replace(/\s{2,}/g, ' ').trim();

  const year       = yearMatch ? parseInt(yearMatch[0]) : null;
  const serial_max = serialMatch ? parseInt(serialMatch[1]) : null;
  const playerWords = playerGuess.toLowerCase().split(/\s+/).filter(Boolean);
  const is_auto    = /\bauto(graph)?\b/i.test(query);
  const is_patch   = /\b(patch|relic|jersey)\b/i.test(query);

  const parallelExclusionList = buildParallelExclusionList(selectedParallelName, allParallelNames);

  return raw.filter(item => {
    const title = (item.title ?? '').toLowerCase();
    if (playerWords.length && playerWords.some((w: string) => !title.includes(w))) return false;
    if (year && !title.includes(String(year))) return false;
    if (cardNumMatch && !new RegExp(`\\b${cardNumMatch[1]}\\b`).test(title)) return false;
    if (/\blot\b/i.test(title)) return false;
    const hasSerial = /\/\d{1,4}\b/.test(title);
    if (!serial_max && hasSerial) return false;
    if (serial_max && !new RegExp(`\\/${serial_max}\\b`).test(title)) return false;
    const hasAuto  = /\bauto(graph)?\b/.test(title);
    const hasPatch = /\b(patch|relic|mem(orabilia)?|jersey)\b/.test(title);
    if (is_auto  && !hasAuto)  return false;
    if (!is_auto  && hasAuto)  return false;
    if (is_patch && !hasPatch) return false;
    if (!is_patch && hasPatch) return false;
    if (/\bssp\b/i.test(title) && !/\bssp\b/i.test(query)) return false;
    if (/\bvariation\b/i.test(title) && !/\bvariation\b/i.test(query)) return false;
    // DB-driven parallel check: reject if title has an excluded parallel
    if (titleHasExcludedParallel(item.title, parallelExclusionList)) return false;
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

function parseGrade(title: string): string {
  const t = title.toLowerCase();
  if (/\bpsa\s*10\b/.test(t)) return 'PSA 10';
  if (/\bpsa\s*9\.5\b/.test(t)) return 'PSA 9.5';
  if (/\bpsa\s*9\b/.test(t)) return 'PSA 9';
  if (/\bbgs\s*9\.5\b/.test(t)) return 'BGS 9.5';
  if (/\bbgs\s*10\b/.test(t)) return 'BGS 10';
  if (/\bsgc\s*10\b/.test(t)) return 'SGC 10';
  if (/\b(psa|bgs|sgc|cgc|csg)\b/.test(t)) return 'Graded';
  return 'Raw';
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
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });

  const supabaseUrl    = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const userId = await verifyJwt(token, supabaseUrl);
  if (!userId) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });

  const { masterCardId, parallelName } = await req.json();
  if (!masterCardId || !parallelName) {
    return new Response(JSON.stringify({ error: 'masterCardId and parallelName required' }), { status: 400, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Fetch the master card row with all joined data
  const { data: masterCard, error: mcError } = await admin
    .from('master_card_definitions')
    .select(`
      id, player, card_number, is_rookie, is_auto, is_patch, serial_max,
      sets ( id, name, releases ( year, name, sport ) )
    `)
    .eq('id', masterCardId)
    .single();

  if (mcError || !masterCard) {
    return new Response(JSON.stringify({ error: 'Master card not found' }), { status: 404, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
  }

  // Fetch all parallel names in this set for exclusion filtering
  const { data: allParallels } = await admin
    .from('set_parallels')
    .select('name')
    .eq('set_id', (masterCard as any).sets.id);

  const allParallelNames = (allParallels as any[])?.map((p: any) => p.name) ?? [];

  const mcd     = masterCard as any;
  const setData = mcd.sets ?? {};
  const release = setData.releases ?? {};

  const cardRow = {
    year:          release.year,
    release_name:  release.name,
    set_name:      setData.name,
    player:        mcd.player,
    card_number:   mcd.card_number,
    parallel_type: parallelName,
    is_auto:       mcd.is_auto,
    is_patch:      mcd.is_patch,
    is_rookie:     mcd.is_rookie,
    serial_max:    mcd.serial_max,
    is_graded:     false, // catalog doesn't grade; we get all comps
    grader:        null,
    grade_value:   null,
  };

  const query = buildCardEbayQuery(cardRow);
  console.log(`[get-card-comps] query: "${query}", parallel: "${parallelName}"`);

  let raw: any[];
  try {
    raw = await fetchSoldListings(query);
  } catch (e: any) {
    return new Response(JSON.stringify({ error: `Scrapechain error: ${e.message}` }), { status: 502, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
  }

  const items = parseAndFilter(raw, query, parallelName, allParallelNames, setData.name ?? undefined);
  console.log(`[get-card-comps] ${raw.length} raw → ${items.length} filtered`);

  // Delete old comps for this master_card + parallel
  await admin.from('card_sold_comps')
    .delete()
    .eq('master_card_id', masterCardId)
    .eq('parallel_name', parallelName);

  // Insert new comps with grade tags
  if (items.length > 0) {
    const rows = items.map((item: any) => {
      const grade = parseGrade(item.title);
      console.log(`[insert] title="${item.title}" → grade="${grade}"`);
      return {
        master_card_id: masterCardId,
        parallel_name: parallelName,
        grade: grade,
        ebay_item_id: item.itemId ?? null,
        title: item.title ?? '',
        price: parseFloat(item.price?.value ?? '0'),
        currency: item.price?.currency ?? 'USD',
        sale_type: typeof item.buyingOptions === 'string' ? item.buyingOptions : 'fixed_price',
        sold_at: item.itemEndDate ?? null,
        url: item.itemWebUrl ?? null,
      };
    });
    console.log(`[insert] Inserting ${rows.length} rows with grades: ${rows.map((r: any) => r.grade).join(', ')}`);
    await admin.from('card_sold_comps').insert(rows);
  }

  // Compute grade averages
  const { data: allCompsData } = await admin
    .from('card_sold_comps')
    .select('price, grade')
    .eq('master_card_id', masterCardId)
    .eq('parallel_name', parallelName);

  const allComps = (allCompsData as any[]) ?? [];
  const rawComps = allComps.filter((c: any) => c.grade === 'Raw');
  const psa10Comps = allComps.filter((c: any) => c.grade === 'PSA 10');
  const psa9Comps = allComps.filter((c: any) => c.grade === 'PSA 9');

  const rawAvg = rawComps.length > 0
    ? rawComps.reduce((s: number, c: any) => s + (c.price ?? 0), 0) / rawComps.length
    : 0;
  const psa10Avg = psa10Comps.length > 0
    ? psa10Comps.reduce((s: number, c: any) => s + (c.price ?? 0), 0) / psa10Comps.length
    : 0;
  const psa9Avg = psa9Comps.length > 0
    ? psa9Comps.reduce((s: number, c: any) => s + (c.price ?? 0), 0) / psa9Comps.length
    : 0;

  // Update user_cards with matching master_card_id + parallel_name
  const { data: userCards } = await admin
    .from('user_cards')
    .select('id, is_graded, grade_value')
    .eq('master_card_id', masterCardId)
    .eq('parallel_name', parallelName);

  for (const card of (userCards as any[]) ?? []) {
    let currentValue = 0;
    if (!card.is_graded) {
      currentValue = rawAvg;
    } else if (card.grade_value === '10' || card.grade_value === '10.0') {
      currentValue = psa10Avg;
    } else if (card.grade_value === '9' || card.grade_value === '9.0') {
      currentValue = psa9Avg;
    } else {
      // Other grades default to raw
      currentValue = rawAvg;
    }

    await admin.from('user_cards')
      .update({
        current_value: currentValue,
        value_refreshed_at: new Date().toISOString(),
      })
      .eq('id', card.id);
  }

  return new Response(
    JSON.stringify({ rawAvg, psa10Avg, psa9Avg, totalCount: items.length, query }),
    { headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } },
  );
});
