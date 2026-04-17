// Shared logic used by both the /api/comps route and the marketValueJob.

// Grading company keywords
export const GRADER_KEYWORDS = ['psa', 'bgs', 'sgc', 'cgc', 'csg', 'beckett'];

// Parallel/variation keywords
export const PARALLEL_KEYWORDS = [
  'refractor', 'holo', 'silver', 'gold', 'red', 'blue', 'green', 'orange',
  'purple', 'pink', 'black', 'white', 'teal', 'yellow', 'brown', 'gray', 'grey',
  'hyper', 'neon', 'aqua', 'mojo', 'wave', 'velocity', 'stars', 'scope',
  'cracked ice', 'disco', 'tiger', 'nebula', 'shimmer', 'choice', 'lava',
  'sp', 'ssp', 'foil', 'logo',
];

// Generic words that appear in eBay card titles without indicating a specific insert/parallel.
export const LISTING_NOISE = new Set([
  'rookie', 'rated', 'serial', 'numbered', 'graded', 'limited', 'edition',
  'insert', 'parallel', 'short', 'print', 'chrome', 'refractor', 'invest',
  'basketball', 'football', 'baseball', 'hockey', 'soccer',
  'ravens', 'steelers', 'browns', 'bengals', 'patriots', 'bills', 'dolphins', 'jets',
  'texans', 'colts', 'jaguars', 'titans', 'broncos', 'raiders', 'chiefs',
  'chargers', 'cowboys', 'giants', 'eagles', 'commanders', 'bears', 'packers',
  'vikings', 'lions', 'falcons', 'panthers', 'saints', 'buccaneers', 'seahawks',
  'rams', 'cardinals', 'niners',
  'lakers', 'warriors', 'celtics', 'knicks', 'bulls', 'heat', 'spurs', 'rockets',
  'nuggets', 'suns', 'maverick', 'mavericks', 'clippers', 'blazers', 'thunder',
  'pacers', 'bucks', 'raptors', 'pistons', 'cavaliers', 'hornets', 'hawks',
  'pelicans', 'grizzlies', 'timberwolves', 'jazz', 'kings', 'magic', 'wizards',
  'nets', 'sixers',
  'yankees', 'redsox', 'dodgers', 'cubs', 'braves', 'astros', 'mets',
  'phillies', 'nationals', 'marlins', 'brewers', 'pirates', 'reds', 'padres',
  'rockies', 'diamondbacks', 'rangers', 'angels', 'athletics', 'mariners',
  'tigers', 'indians', 'guardians', 'twins', 'whitesox', 'royals', 'orioles',
  'bluejays', 'rays',
  'panini', 'topps', 'donruss', 'fleer', 'score', 'ultra', 'select', 'optic',
  'mosaic', 'chronicles', 'certified', 'absolute', 'contenders', 'playoff',
  'treasures', 'prestige', 'titanium', 'spectra', 'bowman', 'stadium',
  'heritage', 'update', 'series', 'national', 'upper', 'deck', 'illusions',
  'revolution', 'majestic', 'lightning', 'genesis', 'zenith', 'phoenix', 'prizm',
  'trading', 'sports', 'card', 'cards', 'single', 'color', 'colour',
]);

function noUnexpectedWords(title: string, query: string): boolean {
  const t = title.toLowerCase();
  const q = query.toLowerCase();
  const titleWords = t.match(/\b[a-z]{6,}\b/g) ?? [];
  return titleWords.every(word => q.includes(word) || LISTING_NOISE.has(word));
}

function noUnexpectedParallels(title: string, query: string): boolean {
  const t = title.toLowerCase();
  const q = query.toLowerCase();
  return !PARALLEL_KEYWORDS.some(k => {
    const re = new RegExp(`\\b${k.replace(/\s+/g, '\\s+')}\\b`);
    return re.test(t) && !q.includes(k);
  });
}

/** Build a structured eBay search query from a user_card row + its joined data. */
export function buildCardEbayQuery(card: any): string {
  const {
    year, release_name, set_name, player, card_number,
    parallel_type, is_auto, is_patch, is_rookie, serial_max,
    is_graded, grader, grade_value,
  } = card;

  const parts: string[] = [String(year ?? ''), release_name ?? ''];

  // Include set name when it's distinctive (not "Base" and not already in the release name)
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

/**
 * Parse a free-text eBay query string into structured filter fields, then filter
 * raw sold results.
 *
 * strictWords=true: also rejects titles with unexpected 6+ char words not in the
 * query or LISTING_NOISE. Use for machine-built queries (card-value, market-value job).
 * Leave false for free-text user queries so eBay's own relevance ranking can work.
 */
export function parseAndFilter(raw: any[], query: string, strictWords = false, setName?: string): any[] {
  const yearMatch     = query.match(/\b(19|20)\d{2}\b/);
  const cardNumMatch  = query.match(/(?:^|\s)#?(\d{1,4})(?:\s|$)/);
  const serialMatch   = query.match(/\/(\d{1,4})\b/);
  const graderFound   = GRADER_KEYWORDS.find(k => new RegExp(`\\b${k}\\b`, 'i').test(query));
  const gradeNumMatch = query.match(/\b(\d+(?:\.\d+)?)\s*(?:gem\s*mint)?$/i);

  const parallelsInQuery = PARALLEL_KEYWORDS.filter(k => new RegExp(`\\b${k}\\b`, 'i').test(query));
  const parallelFromQuery = parallelsInQuery.length ? parallelsInQuery.join(' ') : null;

  const noisePattern = new RegExp(`\\b(${[...LISTING_NOISE].join('|')})\\b`, 'gi');
  const playerGuess = query
    .replace(/\b(19|20)\d{2}\b/, '')
    .replace(/(?:^|\s)#?\d{1,4}(?:\s|$)/, ' ')
    .replace(/\/\d{1,4}\b/, '')
    // Strip set name words so they aren't mistaken for player name words
    .replace(setName ? new RegExp(setName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+'), 'gi') : /(?:)/, '')
    .replace(new RegExp(`\\b(${PARALLEL_KEYWORDS.join('|')})\\b`, 'gi'), '')
    .replace(new RegExp(`\\b(${GRADER_KEYWORDS.join('|')})\\b`, 'gi'), '')
    .replace(/\b(rc|rookie|auto(graph)?|patch|relic|jersey)\b/gi, '')
    .replace(noisePattern, '')
    .replace(/\s{2,}/g, ' ').trim();

  const year        = yearMatch ? parseInt(yearMatch[0]) : null;
  const serial_max  = serialMatch ? parseInt(serialMatch[1]) : null;
  const playerWords = playerGuess.toLowerCase().split(/\s+/).filter(Boolean);
  const parallelStr = parallelFromQuery ?? '';
  const is_auto     = /\bauto(graph)?\b/i.test(query);
  const is_patch    = /\b(patch|relic|jersey)\b/i.test(query);
  const is_graded   = !!graderFound;
  const grader      = graderFound ?? null;
  const grade_value = gradeNumMatch ? gradeNumMatch[1] : null;

  const reject = (item: any, reason: string) => {
    console.log(`[comps/reject] "${item.title}" — ${reason}`);
    return false;
  };

  return raw.filter(item => {
    const title = (item.title ?? '').toLowerCase();

    if (strictWords && playerWords.length && playerWords.some((w: string) => !title.includes(w)))
      return reject(item, 'missing player word');
    if (year && !title.includes(String(year)))
      return reject(item, `missing year ${year}`);
    if (cardNumMatch) {
      const num = cardNumMatch[1];
      if (!new RegExp(`\\b${num}\\b`).test(title)) return reject(item, `missing card number ${num}`);
    }
    if (/\blot\b/i.test(title)) return reject(item, 'lot listing');

    const hasSerial = /\/\d{1,4}\b/.test(title);
    if (strictWords && !serial_max && hasSerial) return reject(item, 'unexpected serial number');
    if (serial_max && !new RegExp(`\\/${serial_max}\\b`).test(title))
      return reject(item, `wrong serial (want /${serial_max})`);

    if (is_graded && grader     && !title.includes(grader.toLowerCase()))
      return reject(item, `missing grader ${grader}`);
    if (is_graded && grade_value && !title.includes(grade_value))
      return reject(item, `missing grade ${grade_value}`);
    const hasGrader = GRADER_KEYWORDS.some(k => new RegExp(`\\b${k}\\b`, 'i').test(title));
    if (!is_graded && hasGrader) return reject(item, 'unexpected grader on raw card');

    const hasAuto  = /\bauto(graph)?\b/.test(title);
    const hasPatch = /\b(patch|relic|mem(orabilia)?|jersey)\b/.test(title);
    if (is_auto  && !hasAuto)  return reject(item, 'missing auto');
    if (strictWords && !is_auto  && hasAuto)  return reject(item, 'unexpected auto');
    if (is_patch && !hasPatch) return reject(item, 'missing patch');
    if (strictWords && !is_patch && hasPatch) return reject(item, 'unexpected patch');

    if (/\bssp\b/i.test(title) && !/\bssp\b/i.test(query)) return reject(item, 'unexpected SSP');
    if (/\bvariation\b/i.test(title) && !/\bvariation\b/i.test(query)) return reject(item, 'unexpected variation');

    if (parallelStr) {
      const parallelWords = parallelStr.toLowerCase().split(/\s+/).filter(Boolean);
      const missing = parallelWords.find(w => !title.includes(w));
      if (missing) return reject(item, `missing parallel word "${missing}"`);
    }
    if (!noUnexpectedParallels(item.title, query)) return reject(item, 'unexpected parallel keyword');
    if (strictWords && !noUnexpectedWords(item.title, query)) {
      const unexpected = (title.match(/\b[a-z]{6,}\b/g) ?? [])
        .find((w: string) => !query.toLowerCase().includes(w) && !LISTING_NOISE.has(w));
      return reject(item, `unexpected word "${unexpected}"`);
    }

    return true;
  });
}

/** Maps eBay buyingOptions array to our 3-value sale_type enum. */
export function resolveSaleType(options: string[]): 'auction' | 'fixed_price' | 'best_offer' {
  if (options.includes('BEST_OFFER')) return 'best_offer';
  if (options.includes('AUCTION'))    return 'auction';
  return 'fixed_price';
}
