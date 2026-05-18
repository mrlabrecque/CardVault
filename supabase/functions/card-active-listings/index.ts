import { createClient } from 'jsr:@supabase/supabase-js@2';
import { fetchActiveListingsBrowse, type EbayActiveListingRow } from '../_shared/ebay_browse_active.ts';
import {
  buildCardEbayQuery,
  parseAndFilterSoldComps,
} from '../_shared/comps_master_refresh.ts';

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
  // Auction before Best Offer — cached rows may be "AUCTION,BEST_OFFER".
  if (fmt.includes('AUCTION')) return 'AUCTION';
  if (fmt.includes('BEST_OFFER')) return 'BEST_OFFER';
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

async function fetchSiblingSetNames(
  admin: ReturnType<typeof createClient>,
  releaseId: string | undefined,
  excludeSetId: string | undefined,
): Promise<string[]> {
  if (!releaseId) return [];
  let q = admin.from('sets').select('name').eq('release_id', releaseId);
  if (excludeSetId) q = q.neq('id', excludeSetId);
  const { data } = await q;
  return ((data as { name?: string }[]) ?? [])
    .map((row) => (row.name ?? '').trim())
    .filter((name) => name.length > 0);
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
        sets ( id, name, release_id, releases ( id, year, name, sport ) )
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
  const releaseId = (setData.release_id ?? setData.releases?.id) as string | undefined;

  const [{ data: allParallels }, siblingSetNames] = await Promise.all([
    admin
      .from('set_parallels')
      .select('name')
      .eq('set_id', setIdForParallels ?? sc.set_id),
    fetchSiblingSetNames(admin, releaseId, setData.id as string | undefined),
  ]);
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
  const filtered = parseAndFilterSoldComps(
    raw,
    query,
    parallelName,
    allParallelNames,
    sc.card_number ?? undefined,
    setData.name ?? undefined,
    undefined,
    siblingSetNames,
  );
  console.log('[card-active-listings] counts:', {
    raw: raw.length,
    filtered: filtered.length,
    siblingSets: siblingSetNames.length,
  });

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
