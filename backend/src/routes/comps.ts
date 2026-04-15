import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { searchSoldListings } from '../services/ebay.service';
import sql from '../db/db';

// Grading company keywords — if any appear in a title for an ungraded card, reject it
const GRADER_KEYWORDS = ['psa', 'bgs', 'sgc', 'cgc', 'csg', 'beckett'];

// Parallel/variation keywords. Any keyword found in a result title but NOT in the
// query string is treated as an unexpected parallel and the result is rejected.
// This handles both base-card searches (reject all parallels) and specific-parallel
// searches (reject other parallels — e.g. searching Silver shouldn't return Gold).
const PARALLEL_KEYWORDS = [
  'refractor', 'holo', 'silver', 'gold', 'red', 'blue', 'green', 'orange',
  'purple', 'pink', 'black', 'white', 'teal', 'yellow', 'brown', 'gray', 'grey',
  'hyper', 'neon', 'aqua', 'mojo', 'wave', 'velocity', 'stars', 'scope',
  'cracked ice', 'disco', 'tiger', 'nebula', 'shimmer', 'choice', 'lava',
  'sp', 'ssp', 'foil', 'logo',
];

// Generic words that appear in eBay card titles without indicating a specific insert/parallel.
// Words in this list are allowed in result titles even if they weren't in the search query.
const LISTING_NOISE = new Set([
  // Card attributes / grading language
  'rookie', 'rated', 'serial', 'numbered', 'graded', 'limited', 'edition',
  'insert', 'parallel', 'short', 'print', 'chrome', 'refractor', 'invest',
  // Sports
  'basketball', 'football', 'baseball', 'hockey', 'soccer',
  // NFL teams
  'ravens', 'steelers', 'browns', 'bengals', 'patriots', 'bills', 'dolphins', 'jets',
  'ravens', 'texans', 'colts', 'jaguars', 'titans', 'broncos', 'raiders', 'chiefs',
  'chargers', 'cowboys', 'giants', 'eagles', 'commanders', 'bears', 'packers',
  'vikings', 'lions', 'falcons', 'panthers', 'saints', 'buccaneers', 'seahawks',
  'rams', 'cardinals', 'niners', 'falcons', 'broncos',
  // NBA teams
  'lakers', 'warriors', 'celtics', 'knicks', 'bulls', 'heat', 'spurs', 'rockets',
  'nuggets', 'suns', 'maverick', 'mavericks', 'clippers', 'blazers', 'thunder',
  'pacers', 'bucks', 'raptors', 'pistons', 'cavaliers', 'hornets', 'hawks',
  'pelicans', 'grizzlies', 'timberwolves', 'jazz', 'kings', 'magic', 'wizards',
  'nets', 'sixers',
  // MLB teams
  'yankees', 'redsox', 'dodgers', 'giants', 'cubs', 'cardinals', 'braves',
  'astros', 'mets', 'phillies', 'nationals', 'marlins', 'brewers', 'pirates',
  'reds', 'padres', 'rockies', 'diamondbacks', 'giants', 'rangers', 'angels',
  'athletics', 'mariners', 'tigers', 'indians', 'guardians', 'twins', 'whitesox',
  'royals', 'orioles', 'bluejays', 'rays',
  // Brands / manufacturers
  'panini', 'topps', 'donruss', 'fleer', 'score', 'ultra', 'select', 'optic',
  'mosaic', 'chronicles', 'certified', 'absolute', 'contenders', 'playoff',
  'treasures', 'prestige', 'titanium', 'spectra', 'bowman', 'stadium',
  'heritage', 'update', 'series', 'national', 'upper', 'deck', 'illusions',
  'revolution', 'majestic', 'lightning', 'genesis', 'zenith', 'phoenix', 'prizm',
  // Common eBay listing filler
  'trading', 'sports', 'card', 'cards', 'single', 'color', 'colour',
]);

// Reject if the title contains a significant word (>5 chars) that is not present
// in the reference query and is not a known generic listing word.
// This catches unexpected insert set names like "Confetti", "Fireworks", "Downtown"
// that PARALLEL_KEYWORDS doesn't cover.
function noUnexpectedWords(title: string, query: string): boolean {
  const t = title.toLowerCase();
  const q = query.toLowerCase();
  const titleWords = t.match(/\b[a-z]{6,}\b/g) ?? [];
  return titleWords.every(word => q.includes(word) || LISTING_NOISE.has(word));
}

// Returns false if the title contains a parallel keyword that the query didn't ask for.
function noUnexpectedParallels(title: string, query: string): boolean {
  const t = title.toLowerCase();
  const q = query.toLowerCase();
  return !PARALLEL_KEYWORDS.some(k => {
    const re = new RegExp(`\\b${k.replace(/\s+/g, '\\s+')}\\b`);
    return re.test(t) && !q.includes(k);
  });
}

function buildEbayQuery(card: any): string {
  const {
    year, release_name, set_name, player, card_number,
    parallel_type, is_auto, is_patch, is_rookie, serial_max,
    is_graded, grader, grade_value,
  } = card;

  const parts: string[] = [String(year ?? ''), release_name ?? '', player ?? ''];
  if (card_number) parts.push(`#${card_number}`);

  // Strip serial suffix from parallel_name (e.g. "Blue Hyper /49" → "Blue Hyper")
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



// Parse a free-text eBay query string into structured filter fields,
// then filter raw results. Used by both the comps search and card-value endpoints.
// strictWords=true: also rejects titles with unexpected 6+ char words not in query or LISTING_NOISE.
//   Use for card-value where the query was machine-built from structured card data.
//   Skip for free-text comps search where the user controls the query.
function parseAndFilter(raw: any[], query: string, strictWords = false): any[] {
  const yearMatch    = query.match(/\b(19|20)\d{2}\b/);
  const cardNumMatch = query.match(/(?:^|\s)#?(\d{1,4})(?:\s|$)/);
  const serialMatch  = query.match(/\/(\d{1,4})\b/);
  const graderFound  = GRADER_KEYWORDS.find(k => new RegExp(`\\b${k}\\b`, 'i').test(query));
  const gradeNumMatch = query.match(/\b(\d+(?:\.\d+)?)\s*(?:gem\s*mint)?$/i);

  const parallelsInQuery = PARALLEL_KEYWORDS.filter(k => new RegExp(`\\b${k}\\b`, 'i').test(query));
  const parallelFromQuery = parallelsInQuery.length ? parallelsInQuery.join(' ') : null;

  // Strip structured tokens and known noise words to isolate the player name
  const noisePattern = new RegExp(`\\b(${[...LISTING_NOISE].join('|')})\\b`, 'gi');
  const playerGuess = query
    .replace(/\b(19|20)\d{2}\b/, '')
    .replace(/(?:^|\s)#?\d{1,4}(?:\s|$)/, ' ')
    .replace(/\/\d{1,4}\b/, '')
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
  const grade_value = gradeNumMatch ? gradeNumMatch[1] : null;

  console.log(`[comps/filter] player="${playerGuess}" year=${year} serial=${serial_max} parallel="${parallelStr}" auto=${is_auto} patch=${is_patch} graded=${is_graded}${grader ? ` grader=${grader} grade=${grade_value}` : ''} strictWords=${strictWords}`);

  const reject = (item: any, reason: string) => {
    console.log(`[comps/reject] "${item.title}" — ${reason}`);
    return false;
  };

  return raw.filter(item => {
    const title = (item.title ?? '').toLowerCase();

    // Player — every word must appear (strict mode only; free-text queries rely on eBay's own relevance)
    if (strictWords && playerWords.length && playerWords.some((w: string) => !title.includes(w))) return reject(item, `missing player word`);

    // Year
    if (year && !title.includes(String(year))) return reject(item, `missing year ${year}`);

    // Card number
    if (cardNumMatch) {
      const num = cardNumMatch[1];
      if (!new RegExp(`\\b${num}\\b`).test(title)) return reject(item, `missing card number ${num}`);
    }

    // Reject lots
    if (/\blot\b/i.test(title)) return reject(item, 'lot listing');

    // Serial — in strict mode, reject numbered cards if none requested or wrong serial.
    // In free-text mode, only enforce if the user actually specified a serial in their query.
    const hasSerial = /\/\d{1,4}\b/.test(title);
    if (strictWords && !serial_max && hasSerial) return reject(item, 'unexpected serial number');
    if (serial_max  && !new RegExp(`\\/${serial_max}\\b`).test(title)) return reject(item, `wrong serial (want /${serial_max})`);

    // Graded — only enforce if grader was in query
    if (is_graded && grader     && !title.includes(grader.toLowerCase())) return reject(item, `missing grader ${grader}`);
    if (is_graded && grade_value && !title.includes(grade_value)) return reject(item, `missing grade ${grade_value}`);

    // Auto
    const hasAuto = /\bauto(graph)?\b/.test(title);
    if (is_auto && !hasAuto) return reject(item, 'missing auto');
    if (strictWords && !is_auto && hasAuto) return reject(item, 'unexpected auto');

    // Patch
    const hasPatch = /\b(patch|relic|mem(orabilia)?|jersey)\b/.test(title);
    if (is_patch && !hasPatch) return reject(item, 'missing patch');
    if (strictWords && !is_patch && hasPatch) return reject(item, 'unexpected patch');

    // SSP / SP / Variation — reject unless query asked for them
    if (/\bssp\b/i.test(title) && !/\bssp\b/i.test(query)) return reject(item, 'unexpected SSP');
    if (/\bvariation\b/i.test(title) && !/\bvariation\b/i.test(query)) return reject(item, 'unexpected variation');

    // Parallel — if parallel keywords were in query, every one must be in title
    if (parallelStr) {
      const parallelWords = parallelStr.toLowerCase().split(/\s+/).filter(Boolean);
      const missing = parallelWords.find(w => !title.includes(w));
      if (missing) return reject(item, `missing parallel word "${missing}"`);
    }
    // Reject titles with unexpected parallel color keywords
    if (!noUnexpectedParallels(item.title, query)) return reject(item, 'unexpected parallel keyword');

    // Strict mode: reject titles with any 4+ char word not in query or LISTING_NOISE.
    if (strictWords && !noUnexpectedWords(item.title, query)) {
      const t = title;
      const q = query.toLowerCase();
      const unexpected = (t.match(/\b[a-z]{6,}\b/g) ?? []).find((w: string) => !q.includes(w) && !LISTING_NOISE.has(w));
      return reject(item, `unexpected word "${unexpected}"`);
    }

    return true;
  });
}

function computeStats(items: any[]): CompsStats {
  const prices = items
    .map((item: any) => parseFloat(item?.price?.value ?? '0'))
    .filter((p: number) => p > 0)
    .sort((a: number, b: number) => a - b);

  if (!prices.length) return { average_price: 0, median_price: 0, min_price: 0, max_price: 0, total_results: 0 };

  const sum = prices.reduce((s: number, p: number) => s + p, 0);
  const mid = Math.floor(prices.length / 2);
  const median = prices.length % 2 === 0
    ? (prices[mid - 1] + prices[mid]) / 2
    : prices[mid];

  return {
    average_price: sum / prices.length,
    median_price:  median,
    min_price:     prices[0],
    max_price:     prices[prices.length - 1],
    total_results: items.length,
  };
}

// Re-export for type reference
type CompsStats = { average_price: number; median_price: number; min_price: number; max_price: number; total_results: number };

// Maps eBay buyingOptions array to our 3-value enum.
// best_offer wins if present because price is the ask, not the final amount.
function resolveSaleType(options: string[]): 'auction' | 'fixed_price' | 'best_offer' {
  if (options.includes('BEST_OFFER')) return 'best_offer';
  if (options.includes('AUCTION'))    return 'auction';
  return 'fixed_price';
}

const router = Router();
router.use(requireAuth);

const HISTORY_LIMIT = 50;

// Simple filter for free-text comps search: drop lot listings only.
// eBay's search engine already matched the keywords — re-checking words here causes false rejections
// for common spelling variants (e.g. "Otani" vs "Ohtani").
function filterByQueryWords(raw: any[]): any[] {
  return raw.filter(item => !/\blot\b/i.test(item.title ?? ''));
}

// POST /api/comps/search
router.post('/search', async (req: AuthRequest, res) => {
  const { query } = req.body;
  if (!query) return res.status(400).json({ error: 'query is required' });

  try {
    const { items: raw } = await searchSoldListings(query);
    const items = filterByQueryWords(raw);
    const stats = computeStats(items);
    const userId = req.userId!;

    // Rolling history: delete oldest if at limit
    const [{ count }] = await sql`SELECT COUNT(*)::int FROM lookup_history WHERE user_id = ${userId}`;
    if (count >= HISTORY_LIMIT) {
      await sql`
        DELETE FROM lookup_history WHERE id = (
          SELECT id FROM lookup_history WHERE user_id = ${userId} ORDER BY timestamp ASC LIMIT 1
        )`;
    }

    await sql`
      INSERT INTO lookup_history (user_id, query, results, timestamp)
      VALUES (${userId}, ${query}, ${sql.json(items as any)}, NOW())`;

    return res.json({ items, stats });
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

// GET /api/comps/history
router.get('/history', async (req: AuthRequest, res) => {
  try {
    const history = await sql`
      SELECT * FROM lookup_history WHERE user_id = ${req.userId!} ORDER BY timestamp DESC`;
    return res.json(history);
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

// POST /api/comps/card-value — fetch eBay sold comps for a saved card and update its current_value
router.post('/card-value', async (req: AuthRequest, res) => {
  const { cardId } = req.body;
  if (!cardId) return res.status(400).json({ error: 'cardId is required' });

  try {
    const userId = req.userId!;

    const [card] = await sql`
      SELECT
        uc.id,
        uc.is_graded,
        uc.grader,
        uc.grade_value,
        COALESCE(mcd.player,      uc.player)       AS player,
        COALESCE(mcd.card_number, uc.card_number)  AS card_number,
        COALESCE(mcd.is_rookie,   uc.is_rookie)    AS is_rookie,
        COALESCE(mcd.is_auto,     uc.is_auto)      AS is_auto,
        COALESCE(mcd.is_patch,    uc.is_patch)     AS is_patch,
        mcd.serial_max,
        uc.parallel_name                           AS parallel_type,
        r.name                                     AS release_name,
        s.name                                     AS set_name,
        r.year,
        r.sport
      FROM user_cards uc
      LEFT JOIN master_card_definitions mcd ON mcd.id = uc.master_card_id
      LEFT JOIN sets s ON s.id = COALESCE(mcd.set_id, uc.set_id)
      LEFT JOIN releases r ON r.id = s.release_id
      WHERE uc.id = ${cardId} AND uc.user_id = ${userId}
    `;

    if (!card) return res.status(404).json({ error: 'Card not found' });

    const query = buildEbayQuery(card);
    console.log(`[comps] eBay query: "${query}"`);

    const { items: raw } = await searchSoldListings(query);
    const items = parseAndFilter(raw, query, /* strictWords */ true);
    console.log(`[comps] ${raw.length} results → ${items.length} after filtering`);

    const prices = items
      .map((item: any) => parseFloat(item?.price?.value ?? '0'))
      .filter((p: number) => p > 0);

    const avgValue =
      prices.length > 0 ? prices.reduce((sum: number, p: number) => sum + p, 0) / prices.length : 0;

    await sql`
      UPDATE user_cards SET current_value = ${avgValue}
      WHERE id = ${cardId} AND user_id = ${userId}
    `;

    // Persist the filtered sold comps linked to this card (replace previous batch)
    await sql`DELETE FROM card_sold_comps WHERE user_card_id = ${cardId}`;

    if (items.length > 0) {
      const rows = items.map((item: any) => ({
        user_card_id: cardId,
        ebay_item_id: item.itemId ?? null,
        title: item.title ?? '',
        price: parseFloat(item?.price?.value ?? '0'),
        currency: item?.price?.currency ?? 'USD',
        sale_type: resolveSaleType(item.buyingOptions ?? []),
        sold_at: item.itemEndDate ?? null,
        url: item.itemWebUrl ?? null,
      }));
      await sql`INSERT INTO card_sold_comps ${sql(rows)}`;
    }

    return res.json({ value: avgValue, soldCount: prices.length, query, items });
  } catch (e: any) {
    console.error('[comps/card-value]', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// GET /api/comps/card-comps/:cardId — fetch persisted sold comps for a card
router.get('/card-comps/:cardId', async (req: AuthRequest, res) => {
  const { cardId } = req.params;
  try {
    const comps = await sql`
      SELECT csc.*
      FROM card_sold_comps csc
      JOIN user_cards uc ON uc.id = csc.user_card_id
      WHERE csc.user_card_id = ${cardId}
        AND uc.user_id = ${req.userId!}
      ORDER BY csc.sold_at DESC NULLS LAST, csc.fetched_at DESC
    `;
    return res.json(comps);
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

export default router;
