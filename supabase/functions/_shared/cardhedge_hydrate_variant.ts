/**
 * Fetches CardHedge `card-details` + optional `all-prices-by-card` backfill
 * to build a payload for [persistGuidePricesOntoMaster].
 * Requests `raw_images_only: true` so placeholder images are not persisted.
 */
import { fetchCardHedgeAllLatestPrices, type CardSearchPriceRow } from './cardhedge_all_prices.ts';
import { normalizePriceEntry } from './cardhedge_persist_master.ts';

const CARD_DETAILS_URL = 'https://api.cardhedger.com/v1/cards/card-details';

function toFiniteNumber(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const n = parseFloat(v.replace(/[^0-9.-]/g, ''));
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/** Same spaced keys as [extractCardHedgeSales] in cardhedge-search-cards. */
function extractCardHedgeSales(row: Record<string, unknown>): {
  sales_7d: number | null;
  sales_30d: number | null;
  gain: number | null;
} {
  const pick = (...keys: string[]): number | null => {
    for (const k of keys) {
      if (Object.prototype.hasOwnProperty.call(row, k)) {
        const n = toFiniteNumber(row[k]);
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

function rowHasPersistablePrices(row: Record<string, unknown>): boolean {
  const p = row.prices;
  if (!Array.isArray(p)) return false;
  for (const e of p) {
    if (normalizePriceEntry(e) !== null) return true;
  }
  return false;
}

function priceRowsToUnknownArray(rows: CardSearchPriceRow[]): unknown[] {
  return rows.map((r) => ({ grade: r.grade, price: r.price }));
}

function normalizeUpstreamImage(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const t = raw.trim();
  if (!t) return null;
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  if (t.startsWith('//')) return `https:${t}`;
  return t;
}

export type HydrateFromCardIdResult = {
  prices: unknown[] | undefined;
  sales7d: number | null;
  sales30d: number | null;
  gain: number | null;
  imageUrl: string | null;
};

/**
 * Returns fields suitable for merging into [persistGuidePricesOntoMaster].
 * `prices` is omitted when nothing usable was found.
 */
export async function hydratePersistFieldsFromCardHedgeCardId(
  apiKey: string,
  cardId: string,
  opts?: { timeoutMs?: number },
): Promise<HydrateFromCardIdResult> {
  const id = cardId.trim();
  const empty: HydrateFromCardIdResult = {
    prices: undefined,
    sales7d: null,
    sales30d: null,
    gain: null,
    imageUrl: null,
  };
  if (!id) return empty;

  const timeoutMs = opts?.timeoutMs ?? 20_000;
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  let chosen: Record<string, unknown> | null = null;
  try {
    const res = await fetch(CARD_DETAILS_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      },
      body: JSON.stringify({ card_id: id, raw_images_only: true }),
      signal: controller.signal,
    });
    const text = await res.text();
    if (!res.ok) return empty;
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      return empty;
    }
    const cards = data.cards;
    if (!Array.isArray(cards) || cards.length === 0) return empty;
    const first = cards[0];
    if (!first || typeof first !== 'object') return empty;
    chosen = first as Record<string, unknown>;
  } catch {
    return empty;
  } finally {
    clearTimeout(t);
  }

  const sales = extractCardHedgeSales(chosen);
  const imageUrl = normalizeUpstreamImage(chosen.image);

  let prices: unknown[] | undefined;
  if (rowHasPersistablePrices(chosen)) {
    prices = (chosen.prices as unknown[]) ?? undefined;
  } else {
    const backfill = await fetchCardHedgeAllLatestPrices(apiKey, id, { timeoutMs });
    if (backfill && backfill.length > 0) {
      prices = priceRowsToUnknownArray(backfill);
    }
  }

  return {
    prices,
    sales7d: sales.sales_7d,
    sales30d: sales.sales_30d,
    gain: sales.gain,
    imageUrl,
  };
}
