import { createClient } from 'jsr:@supabase/supabase-js@2';

const SCRAPECHAIN_URL = 'https://ebay-api.scrapechain.com/findCompletedItems';
const LOOKBACK_DAYS   = 90;
const DAILY_LIMIT     = 10; // top-value cards refreshed each run
const WEEKLY_LIMIT    = 5;  // opted-in cards refreshed each run
const DELAY_MS        = 400; // between Scrapechain calls to stay rate-limit safe

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ── Shared filtering (mirrors refresh-card-value) ─────────────────────────────

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

function buildQuery(card: Record<string, any>): string {
  const { year, release_name, set_name, player, card_number, parallel_name,
          is_auto, is_patch, is_rookie, serial_max, is_graded, grader, grade_value } = card;
  const parts: string[] = [String(year ?? ''), release_name ?? ''];
  const setLabel = (set_name ?? '').trim();
  if (setLabel && setLabel.toLowerCase() !== 'base' &&
      !(release_name ?? '').toLowerCase().includes(setLabel.toLowerCase())) {
    parts.push(setLabel);
  }
  parts.push(player ?? '');
  if (card_number) parts.push(`#${card_number}`);
  const parallelLabel = (parallel_name ?? '').replace(/\s*\/\d+$/, '').trim();
  const attrs: string[] = [];
  if (parallelLabel && parallelLabel !== 'Base') attrs.push(parallelLabel);
  if (is_auto)   attrs.push('Auto');
  if (is_patch)  attrs.push('Patch');
  if (serial_max) attrs.push(`/${serial_max}`);
  if (is_rookie) attrs.push('RC');
  if (is_graded && grader && grade_value) attrs.push(`${grader} ${grade_value}`);
  return [...parts, ...attrs].filter(Boolean).join(' ');
}

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
  return titleWords.every((w: string) => q.includes(w) || LISTING_NOISE.has(w));
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
    .replace(/\b(19|20)\d{2}\b/, '').replace(/(?:^|\s)#?\d{1,4}(?:\s|$)/, ' ')
    .replace(/\/\d{1,4}\b/, '')
    .replace(setName ? new RegExp(setName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+'), 'gi') : /(?:)/, '')
    .replace(new RegExp(`\\b(${PARALLEL_KEYWORDS.join('|')})\\b`, 'gi'), '')
    .replace(new RegExp(`\\b(${GRADER_KEYWORDS.join('|')})\\b`, 'gi'), '')
    .replace(/\b(rc|rookie|auto(graph)?|patch|relic|jersey)\b/gi, '')
    .replace(noisePattern, '').replace(/\s{2,}/g, ' ').trim();

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
    if (!noUnexpectedWords(item.title, query))     return false;
    return true;
  });
}

function resolveSaleType(buying_format: string | null): string {
  const fmt = (buying_format ?? '').toLowerCase();
  if (fmt.includes('auction'))                              return 'auction';
  if (fmt.includes('best offer') || fmt.includes('best_offer')) return 'best_offer';
  return 'fixed_price';
}

async function fetchSoldListings(query: string): Promise<any[]> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - LOOKBACK_DAYS);
  const res = await fetch(SCRAPECHAIN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
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
}

// ── Handler ───────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }

  // Auth: service role key only (this endpoint is called by pg_cron, not users)
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  if (token !== serviceRoleKey) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: CORS_HEADERS });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  // ── Select cards due for refresh ──────────────────────────────────────────

  // Daily tier: top N cards by value, not refreshed in the last 23 hours
  const { data: dailyCards } = await admin
    .from('user_cards')
    .select(`
      id, user_id, current_value, is_graded, grader, grade_value, parallel_name,
      master_card_definitions ( player, card_number, is_rookie, is_auto, is_patch, serial_max,
        sets ( name, releases ( year, name ) )
      )
    `)
    .or('value_refreshed_at.is.null,value_refreshed_at.lt.' + new Date(Date.now() - 23 * 60 * 60 * 1000).toISOString())
    .order('current_value', { ascending: false, nullsFirst: false })
    .limit(DAILY_LIMIT);

  // Weekly tier: opted-in cards staggered by day-of-week hash, not refreshed in 6 days
  // The hash bucketing happens in JS after fetching candidates for today
  const todayDow = new Date().getDay(); // 0=Sun … 6=Sat
  const sixDaysAgo = new Date(Date.now() - 6 * 24 * 60 * 60 * 1000).toISOString();
  const { data: weeklyPool } = await admin
    .from('user_cards')
    .select(`
      id, user_id, current_value, is_graded, grader, grade_value, parallel_name,
      master_card_definitions ( player, card_number, is_rookie, is_auto, is_patch, serial_max,
        sets ( name, releases ( year, name ) )
      )
    `)
    .eq('weekly_price_check', true)
    .or(`value_refreshed_at.is.null,value_refreshed_at.lt.${sixDaysAgo}`)
    .limit(WEEKLY_LIMIT * 7); // fetch a week's worth and bucket locally

  // Simple string hash to assign each card a stable day-of-week bucket
  function dayBucket(id: string): number {
    let h = 0;
    for (let i = 0; i < id.length; i++) { h = (Math.imul(31, h) + id.charCodeAt(i)) | 0; }
    return Math.abs(h) % 7;
  }

  const dailyIds = new Set((dailyCards ?? []).map((c: any) => c.id));
  const weeklyCards = (weeklyPool ?? [])
    .filter((c: any) => !dailyIds.has(c.id) && dayBucket(c.id) === todayDow)
    .slice(0, WEEKLY_LIMIT);

  const batch = [...(dailyCards ?? []), ...weeklyCards];
  console.log(`[auto-refresh] daily=${dailyCards?.length ?? 0} weekly=${weeklyCards.length} total=${batch.length}`);

  if (batch.length === 0) {
    return new Response(JSON.stringify({ refreshed: 0 }), { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } });
  }

  // ── Refresh each card ─────────────────────────────────────────────────────

  let refreshed = 0;
  let errors = 0;

  for (const card of batch) {
    const mcd     = (card as any).master_card_definitions ?? {};
    const setData = mcd.sets ?? {};
    const release = setData.releases ?? {};

    const cardRow = {
      year:          release.year,
      release_name:  release.name,
      set_name:      setData.name,
      player:        mcd.player,
      card_number:   mcd.card_number,
      parallel_name: (card as any).parallel_name,
      is_auto:       mcd.is_auto,
      is_patch:      mcd.is_patch,
      is_rookie:     mcd.is_rookie,
      serial_max:    mcd.serial_max,
      is_graded:     (card as any).is_graded,
      grader:        (card as any).grader,
      grade_value:   (card as any).grade_value,
    };

    const query = buildQuery(cardRow);

    try {
      const raw   = await fetchSoldListings(query);
      const items = parseAndFilter(raw, query, setData.name ?? undefined);
      const prices = items.map((i: any) => parseFloat(i.price?.value ?? '0')).filter((p: number) => p > 0);
      const avgValue = prices.length > 0
        ? prices.reduce((s: number, p: number) => s + p, 0) / prices.length
        : 0;

      await admin.from('user_cards')
        .update({
          previous_value: (card as any).current_value ?? null,
          current_value: avgValue,
          value_refreshed_at: new Date().toISOString(),
        })
        .eq('id', card.id);

      await admin.from('card_sold_comps').delete().eq('user_card_id', card.id);
      if (items.length > 0) {
        await admin.from('card_sold_comps').insert(items.map((item: any) => ({
          user_card_id: card.id,
          ebay_item_id: item.itemId ?? null,
          title:        item.title ?? '',
          price:        parseFloat(item.price?.value ?? '0'),
          currency:     item.price?.currency ?? 'USD',
          sale_type:    typeof item.buyingOptions === 'string' ? item.buyingOptions : 'fixed_price',
          sold_at:      item.itemEndDate ?? null,
          url:          item.itemWebUrl ?? null,
        })));
      }

      console.log(`[auto-refresh] ✓ ${mcd.player} — $${avgValue.toFixed(2)} (${prices.length} comps)`);
      refreshed++;
    } catch (e: any) {
      console.error(`[auto-refresh] ✗ ${mcd.player}: ${e.message}`);
      errors++;
    }

    if (batch.indexOf(card) < batch.length - 1) {
      await new Promise(r => setTimeout(r, DELAY_MS));
    }
  }

  return new Response(
    JSON.stringify({ refreshed, errors }),
    { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } },
  );
});
