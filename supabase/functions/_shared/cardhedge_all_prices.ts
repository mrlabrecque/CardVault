/**
 * CardHedge pricing helpers:
 * - `POST /v1/cards/all-prices-by-card` — full grade ladder for one `card_id`.
 * - `POST /v1/cards/batch-price-estimate` — up to 100 `{ card_id, grade }` pairs per request (OpenAPI).
 */
const ALL_PRICES_BY_CARD_URL = 'https://api.cardhedger.com/v1/cards/all-prices-by-card';

/** `POST /v1/cards/batch-price-estimate` — up to 100 `{ card_id, grade }` pairs per request (OpenAPI). */
const BATCH_PRICE_ESTIMATE_URL = 'https://api.cardhedger.com/v1/cards/batch-price-estimate';

/** OpenAPI `maxItems` for batch-price-estimate. */
export const CARDHEDGE_BATCH_PRICE_MAX_ITEMS = 100;

/**
 * Grades requested during cron refresh (paired with each `card_id`).
 * Wider catalog rows stay intact via merge with existing `current_prices` before persist.
 */
/** Matches app display buckets (`kCardHedgeDisplayGrades` in Flutter). */
export const CARDHEDGE_CRON_BATCH_GRADES: readonly string[] = ['Raw', 'PSA 10', 'PSA 9'];

export type CardSearchPriceRow = { grade: string; price: string };

/** One row from `batch-price-estimate` `results[]`. */
export type BatchPriceEstimateRow = {
  card_id: string;
  grade: string;
  price: number | null;
  error: string | null;
};

export async function fetchCardHedgeAllLatestPrices(
  apiKey: string,
  cardId: string,
  opts?: { timeoutMs?: number },
): Promise<CardSearchPriceRow[] | null> {
  const id = cardId.trim();
  if (!id) return null;
  const timeoutMs = opts?.timeoutMs ?? 15_000;
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(ALL_PRICES_BY_CARD_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      },
      body: JSON.stringify({ card_id: id }),
      signal: controller.signal,
    });
    const text = await res.text();
    if (!res.ok) {
      return null;
    }
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      return null;
    }
    const raw = data.prices;
    if (!Array.isArray(raw)) return null;
    const out: CardSearchPriceRow[] = [];
    for (const item of raw) {
      if (!item || typeof item !== 'object') continue;
      const o = item as Record<string, unknown>;
      const grade = String(o.grade ?? o.Grade ?? '').trim();
      const priceRaw = o.price ?? o.Price;
      if (!grade) continue;
      const priceStr = priceRaw === null || priceRaw === undefined ? '' : String(priceRaw).trim();
      if (!priceStr) continue;
      out.push({ grade, price: priceStr });
    }
    return out.length > 0 ? out : null;
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}

function chunkArray<T>(arr: T[], size: number): T[][] {
  if (size <= 0) return [arr];
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    out.push(arr.slice(i, i + size));
  }
  return out;
}

/** Single POST; returns `null` on transport/parse failure or non-2xx. */
export async function fetchCardHedgeBatchPriceEstimate(
  apiKey: string,
  items: { card_id: string; grade: string }[],
  opts?: { timeoutMs?: number },
): Promise<BatchPriceEstimateRow[] | null> {
  if (items.length === 0) return [];
  if (items.length > CARDHEDGE_BATCH_PRICE_MAX_ITEMS) {
    console.error(
      `[cardhedge_all_prices] batch-price-estimate: items.length ${items.length} > ${CARDHEDGE_BATCH_PRICE_MAX_ITEMS}`,
    );
    return null;
  }
  const timeoutMs = opts?.timeoutMs ?? 45_000;
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(BATCH_PRICE_ESTIMATE_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      },
      body: JSON.stringify({ items }),
      signal: controller.signal,
    });
    const text = await res.text();
    if (!res.ok) {
      console.error(`[cardhedge_all_prices] batch-price-estimate HTTP ${res.status}: ${text.slice(0, 500)}`);
      return null;
    }
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      return null;
    }
    const raw = data.results;
    if (!Array.isArray(raw)) return null;
    const out: BatchPriceEstimateRow[] = [];
    for (const item of raw) {
      if (!item || typeof item !== 'object') continue;
      const o = item as Record<string, unknown>;
      const cardId = String(o.card_id ?? '').trim();
      const grade = String(o.grade ?? '').trim();
      if (!cardId || !grade) continue;
      const priceRaw = o.price;
      const price =
        typeof priceRaw === 'number' && Number.isFinite(priceRaw) && priceRaw > 0
          ? priceRaw
          : null;
      const errRaw = o.error;
      const error = errRaw == null || errRaw === '' ? null : String(errRaw);
      out.push({ card_id: cardId, grade, price, error });
    }
    return out;
  } catch (e) {
    console.error('[cardhedge_all_prices] batch-price-estimate', e);
    return null;
  } finally {
    clearTimeout(t);
  }
}

/**
 * Chunks `items` at [CARDHEDGE_BATCH_PRICE_MAX_ITEMS], POSTs each chunk, concatenates results.
 * Returns `null` if any chunk fails (caller should fall back to per-card `all-prices-by-card`).
 */
export async function fetchCardHedgeBatchPriceEstimateAllChunks(
  apiKey: string,
  items: { card_id: string; grade: string }[],
  opts?: { timeoutMs?: number; delayMsBetweenChunks?: number },
): Promise<BatchPriceEstimateRow[] | null> {
  const chunks = chunkArray(items, CARDHEDGE_BATCH_PRICE_MAX_ITEMS);
  const delayMs = opts?.delayMsBetweenChunks ?? 400;
  const combined: BatchPriceEstimateRow[] = [];
  for (let i = 0; i < chunks.length; i++) {
    const part = await fetchCardHedgeBatchPriceEstimate(apiKey, chunks[i], opts);
    if (part == null) return null;
    combined.push(...part);
    if (i < chunks.length - 1 && delayMs > 0) {
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
  return combined;
}
