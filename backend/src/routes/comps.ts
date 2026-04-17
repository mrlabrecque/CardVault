import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { searchSoldListings } from '../services/ebay.service';
import { buildCardEbayQuery, parseAndFilter, resolveSaleType } from '../services/comps.service';
import sql from '../db/db';

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

    const query = buildCardEbayQuery(card);
    console.log(`[comps] eBay query: "${query}"`);

    const { items: raw } = await searchSoldListings(query);
    const items = parseAndFilter(raw, query, /* strictWords */ true, card.set_name ?? undefined);
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
