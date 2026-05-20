import {
  buildParallelInsertListingRules,
  titleViolatesParallelInsertRules,
} from './parallel_insert_listing_rules.ts';

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

/** Extra tokens that are not reliable set differentiators in listing titles. */
const SET_NAME_NOISE = new Set([
  ...LISTING_NOISE,
  'base', 'hobby', 'blaster', 'retail', 'mega', 'cell', 'pack', 'box',
  'subset', 'draft', 'choice', 'hanger', 'fat', 'jumbo', 'cello',
]);

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function isCatalogBaseParallelName(name: string): boolean {
  return name.trim().toLowerCase() === 'base';
}

/** Words from a set name that should appear in a matching listing title (e.g. "kings", "house"). */
export function distinctiveSetTitleTokens(setName: string): string[] {
  const label = setName.trim();
  if (!label || label.toLowerCase() === 'base') return [];
  const out: string[] = [];
  for (const word of label.toLowerCase().split(/\s+/)) {
    const w = word.replace(/[^a-z0-9]/gi, '');
    if (w.length >= 3 && !SET_NAME_NOISE.has(w)) out.push(w);
  }
  return [...new Set(out)];
}

/** True when the listing title clearly references an insert/subset name. */
export function titleReferencesSet(title: string, setName: string): boolean {
  const label = setName.trim();
  if (!label || label.toLowerCase() === 'base') return false;
  const t = title.toLowerCase();
  const phrase = label.toLowerCase().replace(/\s+/g, ' ');
  if (phrase.length >= 4 && t.includes(phrase)) return true;
  const tokens = distinctiveSetTitleTokens(setName);
  if (tokens.length === 0) return false;
  return tokens.every((tok) => new RegExp(`\\b${escapeRegex(tok)}\\b`, 'i').test(title));
}

/** Active listings: require a set/insert signal when we can derive distinctive tokens from the catalog set name. */
function ourCatalogSetAppearsInActiveListingTitle(title: string, setName: string | undefined): boolean {
  if (!setName?.trim()) return true;
  const label = setName.trim();
  if (label.toLowerCase() === 'base') return true;
  const t = title.toLowerCase();
  const phrase = label.toLowerCase().replace(/\s+/g, ' ');
  if (phrase.length >= 4 && t.includes(phrase)) return true;
  const tokens = distinctiveSetTitleTokens(setName);
  if (tokens.length === 0) return true;
  return tokens.some((tok) => new RegExp(`\\b${escapeRegex(tok)}\\b`, 'i').test(t));
}

export function buildSiblingSetExclusionList(
  ourSetName: string,
  allSetNamesInRelease: string[],
): Set<string> {
  const our = ourSetName.trim().toLowerCase();
  return new Set(
    allSetNamesInRelease
      .map((s) => s.trim())
      .filter((s) => s.length > 0 && s.toLowerCase() !== our),
  );
}

function titleHasExcludedSet(title: string, exclusionList: Set<string>): boolean {
  for (const setName of exclusionList) {
    if (titleReferencesSet(title, setName)) return true;
  }
  return false;
}

/** Exact #card_number match — avoids matching "2" inside "2024" or "#23". */
export function cardNumberMatchesListingTitle(
  title: string,
  cardNumber: string | null | undefined,
): { ok: boolean; reason?: string } {
  if (!cardNumber) return { ok: true };
  const ourNum = String(cardNumber).replace(/^#/, '').trim();
  if (!ourNum || !/^\d{1,4}$/.test(ourNum)) return { ok: true };

  const hashMatches = [...title.matchAll(/#(\d{1,4})\b/gi)].map((m) => m[1]);
  if (hashMatches.length > 0) {
    if (!hashMatches.some((n) => n === ourNum)) {
      return { ok: false, reason: 'card_number_missing' };
    }
    if (hashMatches.some((n) => n !== ourNum)) {
      return { ok: false, reason: 'card_number_conflict' };
    }
    return { ok: true };
  }

  if (new RegExp(`\\b${escapeRegex(ourNum)}\\b`).test(title)) return { ok: true };
  return { ok: false, reason: 'card_number_missing' };
}

/**
 * Active listings: most sellers omit `#` or card number in the title. We still enforce
 * `#…` consistency when hashes are present; otherwise we do **not** require a bare card #.
 */
export function cardNumberMatchesListingTitleActive(
  title: string,
  cardNumber: string | null | undefined,
): { ok: boolean; reason?: string } {
  if (!cardNumber) return { ok: true };
  const ourNum = String(cardNumber).replace(/^#/, '').trim();
  if (!ourNum || !/^\d{1,4}$/.test(ourNum)) return { ok: true };

  const hashMatches = [...title.matchAll(/#(\d{1,4})\b/gi)].map((m) => m[1]);
  if (hashMatches.length > 0) {
    if (!hashMatches.some((n) => n === ourNum)) {
      return { ok: false, reason: 'card_number_missing' };
    }
    if (hashMatches.some((n) => n !== ourNum)) {
      return { ok: false, reason: 'card_number_conflict' };
    }
    return { ok: true };
  }
  if (new RegExp(`\\b${escapeRegex(ourNum)}\\b`).test(title)) return { ok: true };
  return { ok: true };
}

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
  const sel = selectedParallelName.trim().toLowerCase();
  if (isCatalogBaseParallelName(selectedParallelName)) {
    return new Set(allParallelNames.filter((p) => !isCatalogBaseParallelName(p)));
  }
  return new Set(
    allParallelNames.filter(
      (p) => !isCatalogBaseParallelName(p) && p.trim().toLowerCase() !== sel,
    ),
  );
}

function titleHasExcludedParallel(title: string, exclusionList: Set<string>): boolean {
  if (exclusionList.size === 0) return false;
  const t = title.toLowerCase();
  for (const parallel of exclusionList) {
    const escaped = parallel
      .trim()
      .toLowerCase()
      .split(/\s+/)
      .filter((seg) => seg.length > 0)
      .map((seg) => escapeRegex(seg))
      .join('\\s+');
    if (!escaped) continue;
    const re = new RegExp(`\\b${escaped}\\b`, 'i');
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
  siblingSetNames: string[] = [],
  options?: { forActiveListings?: boolean; activeMultiSetRelease?: boolean },
): any[] {
  const forActive = options?.forActiveListings === true;
  /** When the release has multiple catalog sets, tighten insert signals (optional). */
  const activeMultiSet = forActive && options?.activeMultiSetRelease === true;
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
    .replace(/-/g, ' ')
    .replace(/\s{2,}/g, ' ')
    .trim();

  const year = yearMatch ? parseInt(yearMatch[0]) : null;
  const serial_max = serialMatch ? parseInt(serialMatch[1]) : null;
  const playerWords = playerGuess.toLowerCase().split(/\s+/).filter(Boolean);
  const is_auto = /\bauto(graph)?\b/i.test(query);
  const is_patch = /\b(patch|relic|jersey)\b/i.test(query);
  const parallelExclusionList = buildParallelExclusionList(selectedParallelName, allParallelNames);
  const parallelInsertRules = buildParallelInsertListingRules(
    selectedParallelName,
    allParallelNames,
  );
  const siblingSetExclusionList = buildSiblingSetExclusionList(
    setName ?? '',
    siblingSetNames,
  );
  const requireSetInTitle = distinctiveSetTitleTokens(setName ?? '').length > 0;
  const reject = (item: any, reason: string) => {
    if (!debugRejects) return;
    debugRejects.push({
      title: String(item?.title ?? '').slice(0, 180),
      reason,
    });
  };

  return raw.filter((item) => {
    const title = (item.title ?? '').toLowerCase();
    if (!forActive) {
      if (playerWords.length && playerWords.some((w: string) => !title.includes(w))) {
        reject(item, 'player_word_mismatch');
        return false;
      }
    } else {
      const longPw = playerWords.filter((w: string) => w.length >= 4);
      if (longPw.length > 0) {
        if (longPw.some((w: string) => !title.includes(w))) {
          reject(item, 'player_word_mismatch');
          return false;
        }
      } else if (playerWords.length && playerWords.some((w: string) => !title.includes(w))) {
        reject(item, 'player_word_mismatch');
        return false;
      }
    }
    if (year && !title.includes(String(year))) { reject(item, 'year_mismatch'); return false; }
    if (/\blot\b/i.test(title)) { reject(item, 'lot_listing'); return false; }
    const cardNumCheck = forActive
      ? cardNumberMatchesListingTitleActive(item.title ?? '', cardNumber)
      : cardNumberMatchesListingTitle(item.title ?? '', cardNumber);
    if (!cardNumCheck.ok) { reject(item, cardNumCheck.reason ?? 'card_number_mismatch'); return false; }
    // Sold comps: require full insert signal (all distinctive tokens or full phrase).
    if (!forActive && requireSetInTitle && setName && !titleReferencesSet(item.title, setName)) {
      reject(item, 'set_name_missing');
      return false;
    }
    // Active + multi-set release: require at least one distinctive token from **our** set so
    // we do not show the wrong insert. Single-set releases skip this — titles often omit insert names.
    if (activeMultiSet && requireSetInTitle && setName && !ourCatalogSetAppearsInActiveListingTitle(item.title, setName)) {
      reject(item, 'set_name_missing');
      return false;
    }
    // Sibling wrong-set: strict match only (loose "any token" fired on shared words like
    // "donruss"/"optic" across inserts and zeroed results).
    if (titleHasExcludedSet(item.title, siblingSetExclusionList)) {
      reject(item, 'excluded_set_match');
      return false;
    }
    if (titleViolatesParallelInsertRules(item.title ?? '', parallelInsertRules)) {
      reject(item, 'parallel_insert_ambiguity');
      return false;
    }
    const hasSerial = /\/\d{1,4}\b/.test(title);
    // Sold comps: drop titles that mention a print run when our query has none (avoids wrong parallel).
    // Active listings: eBay sellers put /249 etc. in titles constantly — do not use this rule.
    if (!forActive && !serial_max && hasSerial) { reject(item, 'unexpected_serial'); return false; }
    if (serial_max) {
      const hasSlashRun = /\/\d{1,4}\b/.test(title);
      if (forActive) {
        if (hasSlashRun && !new RegExp(`\\/${serial_max}\\b`).test(title)) {
          reject(item, 'serial_mismatch');
          return false;
        }
      } else if (!new RegExp(`\\/${serial_max}\\b`).test(title)) {
        reject(item, 'serial_mismatch');
        return false;
      }
    }
    const hasAuto = /\bauto(graph)?\b/.test(title);
    const hasPatch = /\b(patch|relic|mem(orabilia)?|jersey)\b/.test(title);
    if (is_auto && !hasAuto) { reject(item, 'missing_auto'); return false; }
    if (!forActive && !is_auto && hasAuto) { reject(item, 'unexpected_auto'); return false; }
    if (is_patch && !hasPatch) { reject(item, 'missing_patch'); return false; }
    if (!forActive && !is_patch && hasPatch) { reject(item, 'unexpected_patch'); return false; }
    if (!forActive && /\bssp\b/i.test(title) && !/\bssp\b/i.test(query)) { reject(item, 'unexpected_ssp'); return false; }
    if (!forActive && /\bvariation\b/i.test(title) && !/\bvariation\b/i.test(query)) { reject(item, 'unexpected_variation'); return false; }
    if (titleHasExcludedParallel(item.title, parallelExclusionList)) {
      reject(item, 'excluded_parallel_match');
      return false;
    }
    if (!forActive && !noUnexpectedWords(item.title, query)) { reject(item, 'unexpected_words'); return false; }
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
