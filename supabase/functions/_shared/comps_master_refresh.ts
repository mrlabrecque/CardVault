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

export function buildCardEbayQuery(card: Record<string, unknown>): string {
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
  const unexpected = titleWords.filter((word: string) => !q.includes(word) && !LISTING_NOISE.has(word));
  // Allow a small amount of listing noise that isn't in our static dictionary
  // to avoid dropping otherwise-valid comps.
  return unexpected.length <= 2;
}

export function parseAndFilterSoldComps(
  raw: any[],
  query: string,
  selectedParallelName: string,
  allParallelNames: string[],
  cardNumber?: string | null,
  setName?: string,
  debugRejects?: Array<{ title: string; reason: string }>,
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
  const reject = (item: any, reason: string) => {
    if (!debugRejects) return;
    debugRejects.push({
      title: String(item?.title ?? '').slice(0, 180),
      reason,
    });
  };

  return raw.filter((item) => {
    const title = (item.title ?? '').toLowerCase();
    if (playerWords.length && playerWords.some((w: string) => !title.includes(w))) { reject(item, 'player_word_mismatch'); return false; }
    if (year && !title.includes(String(year))) { reject(item, 'year_mismatch'); return false; }
    if (/\blot\b/i.test(title)) { reject(item, 'lot_listing'); return false; }
    if (cardNumber) {
      const ourNum = String(cardNumber).toLowerCase();
      if (!title.includes(ourNum)) { reject(item, 'card_number_missing'); return false; }
      const otherCardNums = title.match(/#(\d{1,4})\b/g) ?? [];
      if (otherCardNums.some((m: string) => !m.includes(ourNum))) { reject(item, 'card_number_conflict'); return false; }
    }
    const hasSerial = /\/\d{1,4}\b/.test(title);
    if (!serial_max && hasSerial) { reject(item, 'unexpected_serial'); return false; }
    if (serial_max && !new RegExp(`\\/${serial_max}\\b`).test(title)) { reject(item, 'serial_mismatch'); return false; }
    const hasAuto = /\bauto(graph)?\b/.test(title);
    const hasPatch = /\b(patch|relic|mem(orabilia)?|jersey)\b/.test(title);
    if (is_auto && !hasAuto) { reject(item, 'missing_auto'); return false; }
    if (!is_auto && hasAuto) { reject(item, 'unexpected_auto'); return false; }
    if (is_patch && !hasPatch) { reject(item, 'missing_patch'); return false; }
    if (!is_patch && hasPatch) { reject(item, 'unexpected_patch'); return false; }
    if (/\bssp\b/i.test(title) && !/\bssp\b/i.test(query)) { reject(item, 'unexpected_ssp'); return false; }
    if (/\bvariation\b/i.test(title) && !/\bvariation\b/i.test(query)) { reject(item, 'unexpected_variation'); return false; }
    if (titleHasExcludedParallel(item.title, parallelExclusionList)) { reject(item, 'excluded_parallel_match'); return false; }
    if (!noUnexpectedWords(item.title, query)) { reject(item, 'unexpected_words'); return false; }
    return true;
  });
}

export function parseGrade(title: string): string {
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
