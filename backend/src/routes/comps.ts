import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { searchSoldListings } from '../services/ebay.service';
import sql from '../db/db';

// Grading company keywords — if any appear in a title for an ungraded card, reject it
const GRADER_KEYWORDS = ['psa', 'bgs', 'sgc', 'cgc', 'csg', 'beckett'];

// Common parallel/variation keywords — if any appear in a base-card title, reject it
// (We only apply this when parallel_type is Base/null)
const PARALLEL_KEYWORDS = [
  'prizm', 'refractor', 'holo', 'silver', 'gold', 'red', 'blue', 'green', 'orange',
  'purple', 'pink', 'black', 'white', 'hyper', 'neon', 'aqua', 'mojo', 'wave',
  'cracked ice', 'disco', 'tiger', 'nebula', 'shimmer', 'choice',
];

function buildEbayQuery(card: any): string {
  const {
    ebay_search_template, year, set_name, player, card_number,
    parallel_type, is_auto, is_patch, is_rookie, serial_max,
    is_graded, grader, grade_value,
  } = card;

  let base: string;

  if (ebay_search_template) {
    base = (ebay_search_template as string)
      .replace('{year}', year ?? '')
      .replace('{brand}', set_name ?? '')
      .replace('{player_name}', player ?? '')
      .replace('{card_number}', card_number ?? '');
  } else {
    const parts: string[] = [String(year ?? ''), set_name ?? '', player ?? ''];
    if (card_number) parts.push(`#${card_number}`);
    base = parts.filter(Boolean).join(' ');
  }

  // Append card-specific attributes so eBay narrows to the right variant
  const attrs: string[] = [];
  if (parallel_type && parallel_type !== 'Base') attrs.push(parallel_type);
  if (is_rookie)  attrs.push('RC');
  if (is_auto)    attrs.push('Auto');
  if (is_patch)   attrs.push('Patch');
  if (serial_max) attrs.push(`/${serial_max}`);
  if (is_graded && grader && grade_value) attrs.push(`${grader} ${grade_value}`);

  return [base, ...attrs].filter(Boolean).join(' ');
}

function filterResults(items: any[], card: any): any[] {
  const { player, parallel_type, is_auto, is_patch, serial_max, is_graded, grader, grade_value } = card;
  const playerWords = (player ?? '').toLowerCase().split(/\s+/).filter(Boolean);
  const isBase = !parallel_type || parallel_type === 'Base';

  return items.filter(item => {
    const title = (item.title ?? '').toLowerCase();

    // Player's full name must appear in the title
    if (playerWords.some((w: string) => !title.includes(w))) return false;

    // ── Serial number ────────────────────────────────────────────
    // Matches patterns like /10, /25, /49, /99, /149, /199, /249, /299, /999
    const hasSerial = /\/\d{1,4}\b/.test(title);
    if (!serial_max && hasSerial) return false;          // card isn't serial-numbered but result is
    if (serial_max  && !new RegExp(`\\/${serial_max}\\b`).test(title)) return false; // wrong print run

    // ── Grade ────────────────────────────────────────────────────
    const hasGrade = GRADER_KEYWORDS.some(k => new RegExp(`\\b${k}\\b`).test(title));
    if (!is_graded && hasGrade) return false;            // card is raw but result is graded
    if (is_graded  && grader && !title.includes(grader.toLowerCase())) return false;
    if (is_graded  && grade_value && !title.includes(grade_value.toLowerCase())) return false;

    // ── Autograph ────────────────────────────────────────────────
    const hasAuto = /\bauto(graph)?\b/.test(title);
    if (!is_auto && hasAuto) return false;               // card isn't auto but result is
    if (is_auto  && !hasAuto) return false;              // card is auto but result isn't

    // ── Patch / Memorabilia ──────────────────────────────────────
    const hasPatch = /\b(patch|relic|mem(orabilia)?|jersey)\b/.test(title);
    if (!is_patch && hasPatch) return false;
    if (is_patch  && !hasPatch) return false;

    // ── Parallel specificity (base cards only) ───────────────────
    // If this card is a base/non-parallel, reject results that include well-known parallel keywords
    if (isBase && PARALLEL_KEYWORDS.some(k => new RegExp(`\\b${k}\\b`).test(title))) return false;

    return true;
  });
}

// Maps eBay buyingOptions array to our 3-value enum.
// best_offer wins if present because price is the ask, not the final amount.
function resolveSaleType(options: string[]): 'auction' | 'fixed_price' | 'best_offer' {
  if (options.includes('BEST_OFFER')) return 'best_offer';
  if (options.includes('AUCTION'))    return 'auction';
  return 'fixed_price';
}

const router = Router();
router.use(requireAuth);

const HISTORY_LIMIT = 50;

// POST /api/comps/search
router.post('/search', async (req: AuthRequest, res) => {
  const { query } = req.body;
  if (!query) return res.status(400).json({ error: 'query is required' });

  try {
    const results = await searchSoldListings(query);
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
      VALUES (${userId}, ${query}, ${sql.json(results as any)}, NOW())`;

    return res.json(results);
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
        mcd.player,
        mcd.card_number,
        mcd.parallel_type,
        mcd.is_rookie,
        mcd.is_auto,
        mcd.is_patch,
        mcd.serial_max,
        s.name   AS set_name,
        s.year,
        s.sport,
        s.ebay_search_template
      FROM user_cards uc
      JOIN master_card_definitions mcd ON mcd.id = uc.master_card_id
      JOIN sets s ON s.id = mcd.set_id
      WHERE uc.id = ${cardId} AND uc.user_id = ${userId}
    `;

    if (!card) return res.status(404).json({ error: 'Card not found' });

    const query = buildEbayQuery(card);
    console.log(`[comps] eBay query: "${query}"`);

    const raw = (await searchSoldListings(query)) as any[];
    const items = filterResults(raw, card);
    console.log(`[comps] ${raw.length} results → ${items.length} after filtering`);

    const prices = items
      .map((item: any) => parseFloat(item?.price?.value ?? '0'))
      .filter((p: number) => p > 0);

    const avgValue =
      prices.length > 0 ? prices.reduce((sum: number, p: number) => sum + p, 0) / prices.length : 0;

    if (avgValue > 0) {
      await sql`
        UPDATE user_cards SET current_value = ${avgValue}
        WHERE id = ${cardId} AND user_id = ${userId}
      `;
    }

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
