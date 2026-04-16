import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { searchSoldListings } from '../services/ebay.service';
import { buildCardEbayQuery, parseAndFilter } from '../services/comps.service';
import sql from '../db/db';

const router = Router();
router.use(requireAuth);

function avgPrice(items: any[]): number {
  const prices = items
    .map((item: any) => parseFloat(item?.price?.value ?? '0'))
    .filter((p: number) => p > 0);
  if (!prices.length) return 0;
  return prices.reduce((s, p) => s + p, 0) / prices.length;
}

// GET /api/grading/analyze/:userCardId
router.get('/analyze/:userCardId', async (req: AuthRequest, res) => {
  const { userCardId } = req.params;
  const userId = req.userId!;

  try {
    const [card] = await sql`
      SELECT
        uc.id,
        uc.price_paid,
        COALESCE(mcd.player,      uc.player)       AS player,
        COALESCE(mcd.card_number, uc.card_number)  AS card_number,
        COALESCE(mcd.is_rookie,   uc.is_rookie)    AS is_rookie,
        COALESCE(mcd.is_auto,     uc.is_auto)      AS is_auto,
        COALESCE(mcd.is_patch,    uc.is_patch)     AS is_patch,
        mcd.serial_max,
        uc.parallel_name                           AS parallel_type,
        r.name                                     AS release_name,
        r.year,
        r.sport,
        false                                      AS is_graded,
        null                                       AS grader,
        null                                       AS grade_value
      FROM user_cards uc
      LEFT JOIN master_card_definitions mcd ON mcd.id = uc.master_card_id
      LEFT JOIN sets s ON s.id = COALESCE(mcd.set_id, uc.set_id)
      LEFT JOIN releases r ON r.id = s.release_id
      WHERE uc.id = ${userCardId} AND uc.user_id = ${userId}
    `;

    if (!card) return res.status(404).json({ error: 'Card not found' });

    const rawQuery     = buildCardEbayQuery(card);
    const psa9Query    = `${rawQuery} PSA 9`;
    const psa10Query   = `${rawQuery} PSA 10`;
    const gemMintQuery = `${rawQuery} Graded 10 Gem Mint`;

    const psa9Result    = await searchSoldListings(psa9Query);
    await new Promise(r => setTimeout(r, 500));
    const psa10Result   = await searchSoldListings(psa10Query);
    await new Promise(r => setTimeout(r, 500));
    const gemMintResult = await searchSoldListings(gemMintQuery);

    const psa9Items = parseAndFilter(psa9Result.items, psa9Query, true);

    // Merge PSA 10 + Gem Mint results, deduplicating by itemId
    const psa10Filtered    = parseAndFilter(psa10Result.items,   psa10Query,   true);
    const gemMintFiltered  = parseAndFilter(gemMintResult.items, gemMintQuery, true);
    const seen = new Set(psa10Filtered.map((i: any) => i.itemId).filter(Boolean));
    const merged = [...psa10Filtered, ...gemMintFiltered.filter((i: any) => !seen.has(i.itemId))];

    const psa9Avg  = avgPrice(psa9Items);
    const psa10Avg = avgPrice(merged);

    return res.json({
      rawQuery,
      psa9:  { avg: psa9Avg,  count: psa9Items.length,  query: psa9Query },
      psa10: { avg: psa10Avg, count: merged.length, query: psa10Query },
    });
  } catch (e: any) {
    console.error('[grading/analyze]', e.message, e.cause ?? '');
    return res.status(500).json({ error: e.message });
  }
});

export default router;
