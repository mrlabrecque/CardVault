/**
 * CardHedge `POST /v1/cards/all-prices-by-card` — latest prices per grade when
 * `card-search` rows omit or empty `prices` (still returns a valid `card_id`).
 */
const ALL_PRICES_BY_CARD_URL = 'https://api.cardhedger.com/v1/cards/all-prices-by-card';

export type CardSearchPriceRow = { grade: string; price: string };

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
