/** Strip trailing " /99" style serial from parallel display names. */
export function stripSerialSuffix(s: string): string {
  return s.replace(/\s*\/\d+$/, '').trim();
}

export function normLabel(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, ' ');
}

export function isBaseParallelName(parallel: string): boolean {
  const p = normLabel(stripSerialSuffix(parallel));
  return p === '' || p === 'base';
}

/**
 * Match Vault parallel name to CardHedge **`variant`** only (insert/subset lines
 * live in `description` — see `insertSetMatchesDescription`).
 */
export function parallelMatchesVariant(
  expectedParallel: string,
  row: Record<string, unknown>,
): boolean {
  const exp = normLabel(stripSerialSuffix(expectedParallel));
  const vRaw = typeof row.variant === 'string' ? row.variant : '';
  const v = normLabel(vRaw);

  if (isBaseParallelName(expectedParallel)) {
    if (!v || v === 'base') return true;
    if (/\bbase\b/.test(v)) return true;
    return false;
  }

  if (exp.length === 0) return true;

  if (v.includes(exp) || exp.includes(v)) return true;

  const tokens = exp.split(' ').filter((t) => t.length > 2);
  if (tokens.length === 0) {
    return exp.length > 0 && v.includes(exp);
  }
  let hits = 0;
  for (const t of tokens) {
    if (v.includes(t)) hits++;
  }
  const need = Math.max(1, Math.ceil(tokens.length * 0.65));
  return hits >= need;
}

/** Title-case sport string → CardHedge category (e.g. `football` → `Football`). */
export function categoryFromSport(sport: string | undefined | null): string | undefined {
  const s = sport?.trim();
  if (!s) return undefined;
  return s
    .split(/\s+/)
    .filter((w) => w.length > 0)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(' ');
}

/**
 * Vault checklist name for the main sheet (see migrations). CardHedge product
 * strings do not use this phrase — including it returns zero hits from card-search.
 */
export function isVaultCanonicalBaseSetName(name: string | null | undefined): boolean {
  const n = normLabel((name ?? '').trim());
  return n === '' || n === 'base' || n === 'base set';
}

/**
 * CardHedge `set` on card-search: **year** (when not already leading [releaseName])
 * + **release** + **category**. Insert checklists (Fireworks, …) stay off this string
 * and are matched post-fetch on `description` via `insertSetMatchesDescription`.
 */
export function buildCardHedgeSearchSetLabel(input: {
  year?: number | null;
  releaseName?: string | null;
  category?: string | null;
}): string {
  const cat = (input.category ?? '').trim();
  const rel = (input.releaseName ?? '').trim();
  const y = input.year;

  const chunks: string[] = [];
  if (typeof y === 'number' && Number.isFinite(y)) {
    const yStr = String(y);
    if (!rel.toLowerCase().startsWith(yStr.toLowerCase())) {
      chunks.push(yStr);
    }
  }
  if (rel) chunks.push(rel);

  let out = chunks.join(' ').replace(/\s+/g, ' ').trim();
  if (cat) {
    const outL = out.toLowerCase();
    const catL = cat.toLowerCase();
    if (!outL.endsWith(catL) && !outL.includes(` ${catL}`)) {
      out = `${out} ${cat}`.trim();
    }
  }
  return out;
}

/**
 * Vault `setName` / checklist insert (e.g. Fireworks, Downtown). CardHedge carries
 * that line in **`description`**, not in the search `set` string.
 */
export function insertSetMatchesDescription(
  vaultSetName: string | null | undefined,
  row: Record<string, unknown>,
): boolean {
  if (isVaultCanonicalBaseSetName(vaultSetName)) return true;
  const exp = normLabel(String(vaultSetName ?? '').trim());
  if (!exp) return true;
  const desc = typeof row.description === 'string' ? normLabel(row.description) : '';
  if (desc.includes(exp)) return true;
  const tokens = exp.split(' ').filter((t) => t.length > 2);
  if (tokens.length === 0) return desc.includes(exp);
  let hits = 0;
  for (const t of tokens) {
    if (desc.includes(t)) hits++;
  }
  const need = Math.max(1, Math.ceil(tokens.length * 0.65));
  return hits >= need;
}

export function normalizeCardNumber(raw: string | undefined | null): string {
  if (!raw) return '';
  let s = raw.replace(/^#/, '').trim().toLowerCase();
  s = s.replace(/^0+(?=\d)/, '');
  return s;
}

export function cardNumberMatches(expected: string | undefined | null, apiNumber: unknown): boolean {
  if (!expected?.trim()) return true;
  const e = normalizeCardNumber(expected);
  const a = normalizeCardNumber(typeof apiNumber === 'string' ? apiNumber : String(apiNumber ?? ''));
  if (!e || !a) return false;
  return e === a;
}

/** Higher = better fit for [parallelName] on CardHedge **`variant`** only. */
export function parallelScore(parallelName: string, row: Record<string, unknown>): number {
  const exp = normLabel(stripSerialSuffix(parallelName));
  const v = normLabel(typeof row.variant === 'string' ? row.variant : '');

  if (!exp || exp === 'base') {
    if (!v || v === 'base' || /\bbase\b/.test(v)) return 100;
    return 15;
  }

  if (v === exp) return 100;
  if (v.includes(exp) || exp.includes(v)) return 92;

  const tokens = exp.split(' ').filter((t) => t.length > 2);
  if (tokens.length === 0) {
    return v.includes(exp) ? 55 : 0;
  }
  let hits = 0;
  for (const t of tokens) {
    if (v.includes(t)) hits++;
  }
  return Math.min(72, 25 + hits * 16);
}
