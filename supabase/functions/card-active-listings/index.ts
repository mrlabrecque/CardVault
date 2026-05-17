import { createClient } from 'jsr:@supabase/supabase-js@2';
import { fetchActiveListingsBrowse, type EbayActiveListingRow } from '../_shared/ebay_browse_active.ts';

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

  const filtered = raw.filter((item) => {
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
  return filtered;
}

function browseRowToFilterShape(row: EbayActiveListingRow) {
  return {
    title: row.title,
    item_id: row.ebay_item_id,
    price: row.price,
    buying_format: row.buying_format_raw,
    link: row.url,
    image: row.image_url,
    item_end_date: row.itemEndDate,
  };
}

function listingTypeActive(buying_format: string): string {
  const fmt = (buying_format ?? '').toUpperCase();
  if (fmt.includes('BEST_OFFER')) return 'BEST_OFFER';
  if (fmt.includes('AUCTION')) return 'AUCTION';
  return 'FIXED_PRICE';
}

function buildFallbackQueries(params: {
  releaseName?: string;
  setName?: string;
  player?: string;
  cardNumber?: string | null;
  parallelName?: string | null;
  year?: number | null;
}) {
  const {
    releaseName,
    setName,
    player,
    cardNumber,
    parallelName,
    year,
  } = params;

  const yearStr = year ? String(year) : '';
  const cardNumNoHash = cardNumber ? String(cardNumber).replace(/^#/, '') : '';
  const nonBaseParallel =
    parallelName && parallelName.trim().toLowerCase() !== 'base' ? parallelName.trim() : '';

  // Ordered broadening; strict parser still gates final output.
  return [
    [yearStr, releaseName, setName, player, cardNumNoHash ? `#${cardNumNoHash}` : '', nonBaseParallel].filter(Boolean).join(' '),
    [yearStr, releaseName, setName, player, cardNumNoHash, nonBaseParallel].filter(Boolean).join(' '),
    [yearStr, releaseName, player, cardNumNoHash, nonBaseParallel].filter(Boolean).join(' '),
    [releaseName, setName, player, cardNumNoHash, nonBaseParallel].filter(Boolean).join(' '),
  ]
    .map(q => q.replace(/\s{2,}/g, ' ').trim())
    .filter(Boolean);
}

async function fetchActiveWithFallbackQueries(queries: string[]) {
  const seen = new Set<string>();
  const merged: EbayActiveListingRow[] = [];

  for (const q of queries) {
    for (const useCategoryFilter of [true, false]) {
      const rows = await fetchActiveListingsBrowse(q, { useCategoryFilter });

      for (const row of rows) {
        const key = row.ebay_item_id ?? `${row.title}|${row.url ?? ''}|${row.price}`;
        if (seen.has(key)) continue;
        seen.add(key);
        merged.push(row);
      }
    }
  }
  return merged;
}

function parallelNameFromMaster(master: Record<string, unknown>): string {
  const sp = master.set_parallels as Record<string, unknown> | Record<string, unknown>[] | null | undefined;
  if (!sp) return 'Base';
  const row = Array.isArray(sp) ? (sp[0] as Record<string, unknown> | undefined) : (sp as Record<string, unknown>);
  const n = typeof row?.name === 'string' ? row.name.trim() : '';
  return n.length > 0 ? n : 'Base';
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

  let body: { masterCardId?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  }

  const masterCardId = body.masterCardId;
  if (!masterCardId || typeof masterCardId !== 'string' || !masterCardId.trim()) {
    return new Response(JSON.stringify({ error: 'masterCardId required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  const { data: masterCard, error: mcError } = await admin
    .from('master_card_definitions')
    .select(`
      id, is_auto, is_patch, serial_max,
      set_parallels!parallel_id ( name ),
      set_cards (
        player, card_number, is_rookie, set_id,
        sets ( id, name, releases ( year, name, sport ) )
      )
    `)
    .eq('id', masterCardId)
    .single();

  if (mcError || !masterCard) {
    return new Response(JSON.stringify({ error: 'Master card not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
    });
  }

  const sc = (masterCard as any).set_cards ?? {};
  const setData = sc.sets ?? {};
  const setIdForParallels = setData.id as string | undefined;

  const { data: allParallels } = await admin
    .from('set_parallels')
    .select('name')
    .eq('set_id', setIdForParallels ?? sc.set_id);
  const allParallelNames = (allParallels as any[])?.map((p: any) => p.name) ?? [];

  const mcd = masterCard as any;
  const parallelName = parallelNameFromMaster(mcd as Record<string, unknown>);
  const release = setData.releases ?? {};

  const cardRow = {
    year: release.year,
    release_name: release.name,
    set_name: setData.name,
    player: sc.player,
    card_number: sc.card_number,
    parallel_type: parallelName,
    is_auto: mcd.is_auto,
    is_patch: mcd.is_patch,
    is_rookie: sc.is_rookie,
    serial_max: mcd.serial_max,
    is_graded: false,
    grader: null,
    grade_value: null,
  };

  const query = buildCardEbayQuery(cardRow);

  const queryVariants = buildFallbackQueries({
    releaseName: release.name ?? undefined,
    setName: setData.name ?? undefined,
    player: sc.player ?? undefined,
    cardNumber: sc.card_number ?? undefined,
    parallelName,
    year: release.year ?? undefined,
  });
  if (!queryVariants.includes(query)) {
    queryVariants.unshift(query);
  }
  const browseRows = await fetchActiveWithFallbackQueries(queryVariants);
  const raw = browseRows.map(browseRowToFilterShape);
  const filtered = parseAndFilter(raw, query, parallelName, allParallelNames, sc.card_number ?? undefined, setData.name ?? undefined);
  console.log('[card-active-listings] counts:', { raw: raw.length, filtered: filtered.length });

  const items = filtered.map((row: any) => ({
    ebay_item_id: row.item_id,
    title: row.title,
    price: row.price,
    listing_type: listingTypeActive(row.buying_format),
    url: row.link,
    image_url: row.image,
    itemEndDate: row.item_end_date ?? null,
  }));

  return new Response(
    JSON.stringify({
      items,
      query,
      counts: { raw: raw.length, filtered: filtered.length, returned: filtered.length },
    }),
    { headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } },
  );
});
