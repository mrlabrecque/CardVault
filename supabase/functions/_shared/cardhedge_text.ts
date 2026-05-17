import { normalizePriceEntry } from './cardhedge_persist_master.ts';

/** Strip trailing " /99" style print-run suffix from parallel labels (Vault or CardHedge `variant`). */
export function stripSerialSuffix(s: string): string {
  return s.replace(/\s*\/\d+$/, '').trim();
}

/** Catalog parallel labels: `&` → `and` before variant / description matching. */
export function normalizeParallelAmpersand(s: string): string {
  return s.replace(/\s*&\s*/g, ' and ').replace(/\s+/g, ' ').trim();
}

export function normLabel(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, ' ');
}

/** Normalized parallel label for Vault ↔ CardHedge matching. */
export function normParallelSide(s: string): string {
  return normLabel(normalizeParallelAmpersand(stripSerialSuffix(s)));
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Singular/plural variants (e.g. rookie ↔ rookies) for description token checks. */
function parallelTokenWordForms(token: string): string[] {
  const forms = new Set<string>([token]);
  if (token.endsWith('ies') && token.length > 4) {
    forms.add(token.slice(0, -3) + 'y');
    forms.add(token.slice(0, -3));
  } else if (token.endsWith('es') && token.length > 4) {
    forms.add(token.slice(0, -2));
    forms.add(token.slice(0, -1));
  } else if (token.endsWith('s') && token.length > 3) {
    forms.add(token.slice(0, -1));
  } else {
    forms.add(`${token}s`);
    if (token.endsWith('y') && token.length > 2) {
      forms.add(`${token.slice(0, -1)}ies`);
    }
  }
  return [...forms];
}

function descriptionContainsParallelToken(desc: string, token: string): boolean {
  if (!token) return true;
  if (token === 'and') {
    return /\band\b/.test(desc) || desc.includes('&');
  }
  for (const form of parallelTokenWordForms(token)) {
    if (form.length < 2) continue;
    if (new RegExp(`\\b${escapeRegExp(form)}\\b`).test(desc)) return true;
  }
  return desc.includes(token);
}

/**
 * Non-base fallback: every word from the catalog parallel appears in CardHedge `description`
 * (with rookie/rookies-style plural tolerance). Used only when [parallelExactCatalogVariant] finds nothing.
 */
export function parallelDescriptionWordMatch(
  expectedParallel: string,
  row: Record<string, unknown>,
): boolean {
  const exp = normParallelSide(expectedParallel);
  if (!exp || catalogParallelImpliesBase(expectedParallel)) return false;
  const desc = typeof row.description === 'string' ? normLabel(row.description) : '';
  if (!desc) return false;
  const tokens = exp.split(' ').filter((t) => t.length > 0);
  if (tokens.length === 0) return false;
  return tokens.every((t) => descriptionContainsParallelToken(desc, t));
}

/**
 * Strict parallel match: normalized + [stripSerialSuffix] on both catalog
 * [expectedParallel] and CardHedge [row.variant].
 *
 * - Catalog **Base** (empty or "base"): same rules as legacy CardHedge base match —
 *   empty variant, `base`, `base set`, or any `variant` containing the word `base`
 *   (e.g. "Chrome Base"), so Base checklist rows still resolve.
 * - Non-base: normalized variants must be **identical** (e.g. `red` === `red`, not `red stars`).
 */
export function parallelExactCatalogVariant(
  expectedParallel: string,
  row: Record<string, unknown>,
): boolean {
  const exp = normParallelSide(expectedParallel);
  const v = normParallelSide(typeof row.variant === 'string' ? row.variant : '');
  if (!exp || exp === 'base') {
    if (!v || v === 'base' || v === 'base set') return true;
    if (/\bbase\b/.test(v)) return true;
    return false;
  }
  return v === exp;
}

/**
 * Fuzzy score for CardHedge `variant` when **Base** has no [parallelExactCatalogVariant] rows.
 * Not used for non-Base parallels (those require `v === exp` exactly).
 */
/** Catalog parallel is Vault Base (looser CardHedge exact-match bucket). */
export function catalogParallelImpliesBase(parallelName: string): boolean {
  const exp = normParallelSide(parallelName);
  return (
    !exp ||
    exp === 'base' ||
    exp === 'base set' ||
    exp === 'base parallel' ||
    exp === 'base card' ||
    exp === 'baseset' ||
    exp === 'baseparallel'
  );
}

const BASE_VARIANT_PENALTY_RE =
  /\b(silver|gold|red|blue|green|purple|orange|pink|black|prizm|refractor|holo|mojo|wave|scope|velocity|shimmer|sparkle|ice|lazer|laser|disco|hyper|genesis|auto|patch|rc\b|rookie|ssp|numbered|\/\d+)\b/i;

/**
 * Rank CardHedge rows when several qualify as "Base" — prefer plain base variant +
 * checklist description match; never surface alternates to the app.
 */
export function baseVariantPickScore(
  row: Record<string, unknown>,
  setName?: string | null,
): number {
  const v = normParallelSide(typeof row.variant === 'string' ? row.variant : '');
  let score = 0;
  if (!v || v === 'base' || v === 'base set') score += 120;
  else if (v === 'base card' || v === 'base parallel') score += 100;
  else if (/\bbase\b/.test(v) && !BASE_VARIANT_PENALTY_RE.test(v)) score += 55;
  else score += 8;

  const desc = typeof row.description === 'string' ? normLabel(row.description) : '';
  const set = normLabel(String(setName ?? '').trim());
  if (set && !isVaultCanonicalBaseSetName(setName)) {
    if (desc.includes(set)) score += 45;
    const tokens = set.split(' ').filter((t) => t.length > 2);
    let hits = 0;
    for (const t of tokens) {
      if (desc.includes(t)) hits++;
    }
    if (tokens.length > 0) {
      score += Math.round((hits / tokens.length) * 30);
    }
  }

  const prices = row.prices ?? row.current_prices;
  if (Array.isArray(prices) && prices.length > 0) score += 20;

  return score;
}

/** CardHedge sales / gain fields (spaced or snake_case keys). */
export function extractCardHedgeSalesFromRow(row: Record<string, unknown>): {
  sales_7d: number | null;
  sales_30d: number | null;
  gain: number | null;
} {
  const toNum = (v: unknown): number | null => {
    if (typeof v === 'number' && Number.isFinite(v)) return v;
    if (typeof v === 'string') {
      const n = parseFloat(v.replace(/[^0-9.-]/g, ''));
      return Number.isFinite(n) ? n : null;
    }
    return null;
  };
  const pick = (...keys: string[]): number | null => {
    for (const k of keys) {
      if (Object.prototype.hasOwnProperty.call(row, k)) {
        const n = toNum(row[k]);
        if (n !== null) return n;
      }
    }
    return null;
  };
  return {
    sales_7d: pick('7 Day Sales', '7_Day_Sales', 'sales_7d', 'seven_day_sales', 'sevenDaySales'),
    sales_30d: pick('30 Day Sales', '30_Day_Sales', 'sales_30d', 'thirty_day_sales', 'thirtyDaySales'),
    gain: pick('gain', 'Gain'),
  };
}

function pricesFingerprint(row: Record<string, unknown>): string {
  const p = row.prices;
  if (!Array.isArray(p)) return '';
  const entries: { grade: string; price: number }[] = [];
  for (const e of p) {
    const n = normalizePriceEntry(e);
    if (n) entries.push(n);
  }
  entries.sort((a, b) => a.grade.localeCompare(b.grade));
  return JSON.stringify(entries);
}

/** Stable compare key for 7d/30d sales, gain, and grade price rows. */
export function rowMarketFingerprint(row: Record<string, unknown>): string {
  const sales = extractCardHedgeSalesFromRow(row);
  return JSON.stringify({
    sales_7d: sales.sales_7d,
    sales_30d: sales.sales_30d,
    gain: sales.gain,
    prices: pricesFingerprint(row),
  });
}

/** More populated market fields = richer CardHedge row. */
export function rowMarketDetailScore(row: Record<string, unknown>): number {
  const sales = extractCardHedgeSalesFromRow(row);
  let score = 0;
  if (sales.sales_7d != null) score += 12;
  if (sales.sales_30d != null) score += 12;
  if (sales.gain != null) score += 12;
  const p = row.prices;
  if (Array.isArray(p)) {
    for (const e of p) {
      if (normalizePriceEntry(e)) score += 18;
    }
  }
  const img = typeof row.image === 'string' ? row.image.trim() : '';
  if (img.length > 0) score += 6;
  const desc = typeof row.description === 'string' ? row.description.trim() : '';
  if (desc.length > 24) score += 4;
  return score;
}

/**
 * Multiple rows with the same exact `variant`: if 7d/30d/gain/prices all match, pick
 * stably by `card_id`; otherwise pick the row with the most market detail.
 */
export function pickBestAmongExactVariantRows(
  rows: Record<string, unknown>[],
): { chosen: Record<string, unknown>; alternates: Record<string, unknown>[] } {
  if (rows.length === 0) {
    throw new Error('pickBestAmongExactVariantRows: empty pool');
  }
  if (rows.length === 1) {
    return { chosen: rows[0]!, alternates: [] };
  }

  const fingerprints = rows.map((r) => rowMarketFingerprint(r));
  const allSame = fingerprints.every((f) => f === fingerprints[0]);

  if (allSame) {
    const sorted = [...rows].sort((a, b) =>
      String(a.card_id ?? '').localeCompare(String(b.card_id ?? ''))
    );
    return { chosen: sorted[0]!, alternates: [] };
  }

  const ranked = [...rows].sort((a, b) => {
    const ds = rowMarketDetailScore(b) - rowMarketDetailScore(a);
    if (ds !== 0) return ds;
    return String(a.card_id ?? '').localeCompare(String(b.card_id ?? ''));
  });
  return { chosen: ranked[0]!, alternates: [] };
}

/** Single best Base row; [alternates] always empty. */
export function pickBestBaseVariantRow(
  rows: Record<string, unknown>[],
  setName?: string | null,
): { chosen: Record<string, unknown>; alternates: Record<string, unknown>[] } {
  if (rows.length === 0) {
    throw new Error('pickBestBaseVariantRow: empty pool');
  }
  const ranked = [...rows].sort((a, b) => {
    const ds = baseVariantPickScore(b, setName) - baseVariantPickScore(a, setName);
    if (ds !== 0) return ds;
    return String(a.card_id ?? '').localeCompare(String(b.card_id ?? ''));
  });
  const topScore = baseVariantPickScore(ranked[0]!, setName);
  const topTier = ranked.filter((r) => baseVariantPickScore(r, setName) === topScore);
  if (topTier.length <= 1) {
    return { chosen: ranked[0]!, alternates: [] };
  }
  const winnerVariant = normParallelSide(
    typeof ranked[0]!.variant === 'string' ? ranked[0]!.variant : '',
  );
  const sameVariant = topTier.filter((r) => {
    const v = normParallelSide(typeof r.variant === 'string' ? r.variant : '');
    return v === winnerVariant;
  });
  return pickBestAmongExactVariantRows(sameVariant.length > 0 ? sameVariant : topTier);
}

export function parallelScore(parallelName: string, row: Record<string, unknown>): number {
  const exp = normParallelSide(parallelName);
  const v = normParallelSide(typeof row.variant === 'string' ? row.variant : '');

  if (!exp || exp === 'base') {
    if (!v || v === 'base' || /\bbase\b/.test(v)) return 100;
    return 15;
  }

  if (v === exp) return 100;

  // Base-only fuzzy: never treat `red` as matching `red stars`.
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
 * CardHedge `search` string: **Player + Year + Release + Number + Set**
 * (e.g. `Jalen Hurts 2025 Donruss Football #GK-JHS Gridiron Kings`).
 * Parallel is resolved post-fetch on `variant`, not in this string.
 */
export function buildCardHedgeCardSearchString(input: {
  player: string;
  year?: number | null;
  releaseName?: string | null;
  cardNumber?: string | null;
  setName?: string | null;
}): string {
  const parts: string[] = [];
  const player = input.player.trim();
  if (player) parts.push(player);
  const rel = (input.releaseName ?? '').trim();
  if (typeof input.year === 'number' && Number.isFinite(input.year)) {
    const yStr = String(Math.trunc(input.year));
    if (!rel.toLowerCase().startsWith(yStr.toLowerCase())) {
      parts.push(yStr);
    }
  }
  if (rel) parts.push(rel);
  const cn = (input.cardNumber ?? '').trim().replace(/^#/, '');
  if (cn) parts.push(`#${cn}`);
  const set = (input.setName ?? '').trim();
  if (set && !isVaultCanonicalBaseSetName(set)) parts.push(set);
  return parts.join(' ').replace(/\s+/g, ' ').trim();
}

/**
 * POST `/v1/cards/card-search` body — `category`, `page`, `page_size`, and `search`
 * (plus optional `raw_images_only`, `rookie`). No separate `player` / `set` fields.
 */
export function buildCardHedgeCardSearchBody(input: {
  category: string;
  player: string;
  year?: number | null;
  releaseName?: string | null;
  setName?: string | null;
  cardNumber?: string | null;
  pageSize?: number;
  page?: number;
  rawImagesOnly?: boolean;
  rookie?: string | null;
}): Record<string, unknown> {
  const category = input.category.trim();
  const search = buildCardHedgeCardSearchString({
    player: input.player,
    year: input.year,
    releaseName: input.releaseName,
    cardNumber: input.cardNumber,
    setName: input.setName,
  });
  const body: Record<string, unknown> = {
    category,
    search,
    page_size: Math.min(100, Math.max(1, input.pageSize ?? 100)),
    page: Math.max(1, input.page ?? 1),
  };
  if (input.rawImagesOnly === true) body.raw_images_only = true;
  const rookie = input.rookie?.trim();
  if (rookie) body.rookie = rookie;
  return body;
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
