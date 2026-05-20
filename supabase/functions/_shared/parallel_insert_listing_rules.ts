/**
 * Heuristics for matching **marketplace listing titles** to a **catalog parallel** when
 * several parallels in the same set share a long common suffix (e.g. "… Black Pandora").
 *
 * **Limits:** This is token overlap on display names, not a taxonomy of inserts. It will
 * miss abbreviations and can false-positive on prose. Prefer stable catalog strings on
 * `set_parallels.name`; tune `GUARDED_SINGLE_TOKEN_PREFIXES` when a single token collides
 * with another product line (see `threads` vs "Triple Threads").
 *
 * **Reuse:** Import [buildParallelInsertListingRules] once per request/batch, then
 * [titleViolatesParallelInsertRules] per listing title.
 */

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parallelNameTokens(name: string): string[] {
  return name
    .trim()
    .toLowerCase()
    .split(/\s+/)
    .map((t) => t.replace(/[^a-z0-9]/gi, ''))
    .filter((t) => t.length > 0);
}

const MIN_SHARED_SUFFIX_TOKENS = 2;
const MIN_MULTIWORD_PREFIX_TOKENS = 2;

/**
 * Single-token prefixes from another parallel that need an "unless" guard on the title
 * (bare `\\btoken\\b` is too noisy alone).
 */
export const GUARDED_SINGLE_TOKEN_PREFIXES: ReadonlyArray<{ token: string; unless: RegExp }> = [
  { token: 'threads', unless: /\btriple\s+threads\b/i },
];

export type ParallelInsertListingRules = {
  readonly multiWordPhrases: string[];
  readonly guardedTokens: ReadonlyArray<{ token: string; unless: RegExp }>;
};

function titleContainsWholeWordPhrase(title: string, phrase: string): boolean {
  const words = phrase.trim().toLowerCase().split(/\s+/).filter((w) => w.length > 0);
  if (words.length === 0) return false;
  const t = title.toLowerCase();
  return words.every((w) => new RegExp(`\\b${escapeRegex(w)}\\b`, 'i').test(t));
}

/**
 * Builds reject rules from [selectedParallelName] vs [allParallelNames] (same set).
 * Call once; then use [titleViolatesParallelInsertRules] for each title.
 */
export function buildParallelInsertListingRules(
  selectedParallelName: string,
  allParallelNames: string[],
): ParallelInsertListingRules {
  const sel = selectedParallelName.trim();
  const phrases = new Set<string>();
  const guarded: Array<{ token: string; unless: RegExp }> = [];
  const seenGuardTokens = new Set<string>();

  if (!sel || sel.toLowerCase() === 'base') {
    return { multiWordPhrases: [], guardedTokens: [] };
  }

  const selTok = parallelNameTokens(sel);
  if (selTok.length < MIN_SHARED_SUFFIX_TOKENS) {
    return { multiWordPhrases: [], guardedTokens: [] };
  }

  const seenLower = sel.toLowerCase();

  for (const raw of allParallelNames) {
    const p = raw?.trim() ?? '';
    if (!p || p.toLowerCase() === 'base') continue;
    if (p.toLowerCase() === seenLower) continue;

    const pTok = parallelNameTokens(p);
    if (pTok.length < MIN_SHARED_SUFFIX_TOKENS) continue;

    let i = selTok.length - 1;
    let j = pTok.length - 1;
    let common = 0;
    while (i >= 0 && j >= 0 && selTok[i] === pTok[j]) {
      common++;
      i--;
      j--;
    }
    if (common < MIN_SHARED_SUFFIX_TOKENS) continue;

    const prefixTok = pTok.slice(0, pTok.length - common);
    if (prefixTok.length === 0) continue;

    if (prefixTok.length >= MIN_MULTIWORD_PREFIX_TOKENS) {
      phrases.add(prefixTok.join(' '));
      continue;
    }

    if (prefixTok.length === 1) {
      const w = prefixTok[0].toLowerCase();
      const guard = GUARDED_SINGLE_TOKEN_PREFIXES.find((g) => g.token.toLowerCase() === w);
      if (!guard || seenGuardTokens.has(guard.token)) continue;
      seenGuardTokens.add(guard.token);
      guarded.push(guard);
    }
  }

  return {
    multiWordPhrases: [...phrases],
    guardedTokens: guarded,
  };
}

/** True if the title hits a conflicting insert phrase / guarded token. */
export function titleViolatesParallelInsertRules(
  title: string,
  rules: ParallelInsertListingRules,
): boolean {
  const raw = String(title ?? '');
  for (const phrase of rules.multiWordPhrases) {
    if (titleContainsWholeWordPhrase(raw, phrase)) return true;
  }
  for (const g of rules.guardedTokens) {
    if (
      new RegExp(`\\b${escapeRegex(g.token)}\\b`, 'i').test(raw) &&
      !g.unless.test(raw)
    ) {
      return true;
    }
  }
  return false;
}
