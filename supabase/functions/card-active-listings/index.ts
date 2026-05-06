import { createClient } from 'jsr:@supabase/supabase-js@2';

const SCRAPECHAIN_ACTIVE_URL = 'https://ebay-api.scrapechain.com/findActiveItems';

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
  if (is_auto) attrs.push('Auto');
  if (is_patch) attrs.push('Patch');
  if (serial_max) attrs.push(`/${serial_max}`);
  if (is_rookie) attrs.push('RC');
  if (is_graded && grader && grade_value) attrs.push(`${grader} ${grade_value}`);

  return [...parts, ...attrs].filter(Boolean).join(' ');
}

function buildParallelExclusionList(selectedParallelName: string, allParallelNames: string[]): Set<string> {
  if (selectedParallelName === 'Base') {
    return new Set(allParallelNames.filter(p => p !== 'Base'));
  }
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

function noUnexpectedWords(title: string, query: string): boolean {
  const t = title.toLowerCase();
  const q = query.toLowerCase();
  const titleWords = t.match(/\b[a-z]{6,}\b/g) ?? [];
  return titleWords.every((word: string) => q.includes(word) || LISTING_NOISE.has(word));
}

/** Mirrors refresh-comps parseAndFilter — uses item.title */
function parseAndFilter(
  raw: any[],
  query: string,
  selectedParallelName: string,
  allParallelNames: string[],
  cardNumber?: string | null,
  setName?: string,
): any[] {
  const yearMatch = query.match(/\b(19|20)\d{2}\b/);
  const serialMatch = query.match(/\/(\d{1,4})\b/);
  const noisePattern = new RegExp(`\\b(${[...LISTING_NOISE].join('|')})\\b`, 'gi');
  const playerGuess = query
    .replace(/\b(19|20)\d{2}\b/, '')
    .replace(/(?:^|\s)#?\d{1,4}(?:\s|$)/, ' ')
    .replace(/\/\d{1,4}\b/, '')
    .replace(setName ? new RegExp(setName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+'), 'gi') : /(?:)/, '')
    .replace(/\b(rc|rookie|auto(graph)?|patch|relic|jersey)\b/gi, '')
    .replace(noisePattern, '')
    .replace(/\s{2,}/g, ' ')
    .trim();

  const year = yearMatch ? parseInt(yearMatch[0]) : null;
  const serial_max = serialMatch ? parseInt(serialMatch[1]) : null;
  const playerWords = playerGuess.toLowerCase().split(/\s+/).filter(Boolean);
  const is_auto = /\bauto(graph)?\b/i.test(query);
  const is_patch = /\b(patch|relic|jersey)\b/i.test(query);
  const parallelExclusionList = buildParallelExclusionList(selectedParallelName, allParallelNames);

  return raw.filter((item) => {
    const title = (item.title ?? '').toLowerCase();
    if (playerWords.length && playerWords.some((w: string) => !title.includes(w))) return false;
    if (year && !title.includes(String(year))) return false;
    if (/\blot\b/i.test(title)) return false;
    if (cardNumber) {
      const ourNum = String(cardNumber).toLowerCase();
      if (!title.includes(ourNum)) return false;
      const otherCardNums = title.match(/#(\d{1,4})\b/g) ?? [];
      if (otherCardNums.some((m: string) => !m.includes(ourNum))) return false;
    }
    const hasSerial = /\/\d{1,4}\b/.test(title);
    if (!serial_max && hasSerial) return false;
    if (serial_max && !new RegExp(`\\/${serial_max}\\b`).test(title)) return false;
    const hasAuto = /\bauto(graph)?\b/.test(title);
    const hasPatch = /\b(patch|relic|mem(orabilia)?|jersey)\b/.test(title);
    if (is_auto && !hasAuto) return false;
    if (!is_auto && hasAuto) return false;
    if (is_patch && !hasPatch) return false;
    if (!is_patch && hasPatch) return false;
    if (/\bssp\b/i.test(title) && !/\bssp\b/i.test(query)) return false;
    if (/\bvariation\b/i.test(title) && !/\bvariation\b/i.test(query)) return false;
    if (titleHasExcludedParallel(item.title, parallelExclusionList)) return false;
    if (!noUnexpectedWords(item.title, query)) return false;
    return true;
  });
}

async function fetchActiveListings(query: string): Promise<any[]> {
  try {
    const res = await fetch(SCRAPECHAIN_ACTIVE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ keywords: query, max_search_results: 40, category_id: '261328' }),
    });
    if (!res.ok) return [];
    const data = await res.json();
    return (data.products ?? []).map((p: any) => ({
      title: p.title ?? '',
      item_id: p.item_id ?? null,
      price: parseFloat(String(p.price ?? p.sale_price ?? '0')),
      buying_format: p.buying_format ?? '',
      link: p.link ?? p.url ?? null,
      image: p.image ?? p.image_url ?? null,
    })).filter((row: any) => row.price > 0 && row.title);
  } catch {
    return [];
  }
}

function listingTypeActive(buying_format: string): string {
  const fmt = (buying_format ?? '').toLowerCase();
  return fmt.includes('auction') ? 'AUCTION' : 'FIXED_PRICE';
}

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
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  function b64urlToBytes(b64url: string): Uint8Array {
    const b64 = b64url.replace(/-/g, '+').replace(/_/g, '/');
    return Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  }

  function b64urlToJson(b64url: string): any {
    return JSON.parse(new TextDecoder().decode(b64urlToBytes(b64url)));
  }

  let cachedJwks: any[] | null = null;
  async function getJwks(url: string): Promise<any[]> {
    if (cachedJwks) return cachedJwks;
    const res = await fetch(`${url}/auth/v1/.well-known/jwks.json`);
    const data = await res.json();
    cachedJwks = data.keys ?? [];
    return cachedJwks!;
  }

  async function verifyJwt(token: string, url: string): Promise<string | null> {
    try {
      const parts = token.split('.');
      if (parts.length !== 3) return null;
      const header = b64urlToJson(parts[0]);
      const payload = b64urlToJson(parts[1]);
      const jwks = await getJwks(url);
      const jwk = jwks.find((k: any) => k.kid === header.kid) ?? jwks[0];
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
    } catch {
      return null;
    }
  }

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const userId = await verifyJwt(token, supabaseUrl);
  if (!userId) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  }

  let body: { masterCardId?: string; parallelName?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  }

  const masterCardId = body.masterCardId;
  const parallelName = body.parallelName;
  if (!masterCardId || parallelName === undefined || parallelName === null) {
    return new Response(JSON.stringify({ error: 'masterCardId and parallelName required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  const { data: masterCard, error: mcError } = await admin
    .from('master_card_definitions')
    .select(`
      id, player, card_number, is_rookie, is_auto, is_patch, serial_max,
      sets ( id, name, releases ( year, name, sport ) )
    `)
    .eq('id', masterCardId)
    .single();

  if (mcError || !masterCard) {
    return new Response(JSON.stringify({ error: 'Master card not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  }

  const { data: allParallels } = await admin
    .from('set_parallels')
    .select('name')
    .eq('set_id', (masterCard as any).sets.id);

  const allParallelNames = (allParallels as any[])?.map((p: any) => p.name) ?? [];

  const mcd = masterCard as any;
  const setData = mcd.sets ?? {};
  const release = setData.releases ?? {};

  const cardRow = {
    year: release.year,
    release_name: release.name,
    set_name: setData.name,
    player: mcd.player,
    card_number: mcd.card_number,
    parallel_type: parallelName,
    is_auto: mcd.is_auto,
    is_patch: mcd.is_patch,
    is_rookie: mcd.is_rookie,
    serial_max: mcd.serial_max,
    is_graded: false,
    grader: null,
    grade_value: null,
  };

  const query = buildCardEbayQuery(cardRow);

  const raw = await fetchActiveListings(query);
  const filtered = parseAndFilter(raw, query, parallelName, allParallelNames, mcd.card_number ?? undefined, setData.name ?? undefined);

  const items = filtered.map((row: any) => ({
    ebay_item_id: row.item_id,
    title: row.title,
    price: row.price,
    listing_type: listingTypeActive(row.buying_format),
    url: row.link,
    image_url: row.image,
  }));

  return new Response(
    JSON.stringify({ items, query }),
    { headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } },
  );
});
