import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import sql from '../db/db';
import { runAlertJob } from '../jobs/alertJob';

const router = Router();
router.use(requireAuth);

router.post('/check-now', async (req: AuthRequest, res) => {
  try {
    const result = await runAlertJob(req.userId!);
    return res.json(result);
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

router.get('/triggered-count', async (req: AuthRequest, res) => {
  try {
    const [{ count }] = await sql`
      SELECT COUNT(*)::int AS count FROM wishlist
      WHERE user_id = ${req.userId!} AND alert_status = 'triggered'`;
    return res.json({ count });
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

router.get('/', async (req: AuthRequest, res) => {
  try {
    const items = await sql`
      SELECT * FROM wishlist
      WHERE user_id = ${req.userId!}
      ORDER BY created_at DESC`;

    // Attach matches for any triggered items in a single query
    const triggeredIds = items.filter(i => i.alert_status === 'triggered').map(i => i.id);
    let matchesByItem: Record<string, any[]> = {};

    if (triggeredIds.length > 0) {
      const matches = await sql`
        SELECT * FROM wishlist_matches
        WHERE wishlist_id = ANY(${triggeredIds})
        ORDER BY wishlist_id, price ASC`;

      for (const m of matches) {
        if (!matchesByItem[m.wishlist_id]) matchesByItem[m.wishlist_id] = [];
        matchesByItem[m.wishlist_id].push(m);
      }
    }

    const result = items.map(item => ({
      ...item,
      matches: matchesByItem[item.id] ?? [],
    }));

    return res.json(result);
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

router.post('/', async (req: AuthRequest, res) => {
  const {
    player, year, set_name, parallel, card_number,
    is_rookie, is_auto, is_patch, serial_max, grade,
    ebay_query, target_price, exclude_terms,
  } = req.body;

  try {
    const [item] = await sql`
      INSERT INTO wishlist (
        user_id, player, year, set_name, parallel, card_number,
        is_rookie, is_auto, is_patch, serial_max, grade,
        ebay_query, target_price, exclude_terms, alert_status
      ) VALUES (
        ${req.userId!}, ${player ?? null}, ${year ?? null}, ${set_name ?? null},
        ${parallel ?? null}, ${card_number ?? null},
        ${is_rookie ?? false}, ${is_auto ?? false}, ${is_patch ?? false},
        ${serial_max ?? null}, ${grade ?? null},
        ${ebay_query ?? null}, ${target_price ?? null},
        ${exclude_terms ?? []}, 'active'
      )
      RETURNING *`;
    return res.status(201).json(item);
  } catch (e: any) {
    return res.status(400).json({ error: e.message });
  }
});

router.patch('/:id', async (req: AuthRequest, res) => {
  const {
    player, year, set_name, parallel, card_number,
    is_rookie, is_auto, is_patch, serial_max, grade,
    ebay_query, target_price, exclude_terms, alert_status,
  } = req.body;

  // Build only the fields that were sent
  const updates: Record<string, any> = {};
  if ('player'        in req.body) updates.player        = player;
  if ('year'          in req.body) updates.year          = year;
  if ('set_name'      in req.body) updates.set_name      = set_name;
  if ('parallel'      in req.body) updates.parallel      = parallel;
  if ('card_number'   in req.body) updates.card_number   = card_number;
  if ('is_rookie'     in req.body) updates.is_rookie     = is_rookie;
  if ('is_auto'       in req.body) updates.is_auto       = is_auto;
  if ('is_patch'      in req.body) updates.is_patch      = is_patch;
  if ('serial_max'    in req.body) updates.serial_max    = serial_max;
  if ('grade'         in req.body) updates.grade         = grade;
  if ('ebay_query'    in req.body) updates.ebay_query    = ebay_query;
  if ('target_price'  in req.body) updates.target_price  = target_price;
  if ('exclude_terms' in req.body) updates.exclude_terms = exclude_terms;
  if ('alert_status'  in req.body) updates.alert_status  = alert_status;

  if (Object.keys(updates).length === 0) {
    return res.status(400).json({ error: 'No fields to update' });
  }

  try {
    const [item] = await sql`
      UPDATE wishlist SET ${sql(updates)}
      WHERE id = ${req.params.id} AND user_id = ${req.userId!}
      RETURNING *`;
    if (!item) return res.status(404).json({ error: 'Not found' });
    return res.json(item);
  } catch (e: any) {
    return res.status(400).json({ error: e.message });
  }
});

// Dismiss a specific match — removes it from wishlist_matches and blocks it from ever matching again
router.delete('/:id/matches/:matchId', async (req: AuthRequest, res) => {
  try {
    const { id, matchId } = req.params;

    // Get the ebay_item_id before deleting
    const [match] = await sql`
      SELECT wm.ebay_item_id FROM wishlist_matches wm
      JOIN wishlist w ON w.id = wm.wishlist_id
      WHERE wm.id = ${matchId} AND w.id = ${id} AND w.user_id = ${req.userId!}`;

    if (!match) return res.status(404).json({ error: 'Match not found' });

    // Delete the match row
    await sql`DELETE FROM wishlist_matches WHERE id = ${matchId}`;

    // Add ebay_item_id to the dismissed list (if it has one)
    if (match.ebay_item_id) {
      await sql`
        UPDATE wishlist
        SET dismissed_ebay_ids = array_append(dismissed_ebay_ids, ${match.ebay_item_id})
        WHERE id = ${id} AND user_id = ${req.userId!}`;
    }

    // If no matches remain, reset alert_status back to active
    const [{ count }] = await sql`
      SELECT COUNT(*)::int AS count FROM wishlist_matches WHERE wishlist_id = ${id}`;

    if (count === 0) {
      await sql`
        UPDATE wishlist SET alert_status = 'active', last_seen_price = NULL
        WHERE id = ${id} AND user_id = ${req.userId!}`;
    } else {
      // Update last_seen_price to the new cheapest match
      await sql`
        UPDATE wishlist SET last_seen_price = (
          SELECT MIN(price) FROM wishlist_matches WHERE wishlist_id = ${id}
        ) WHERE id = ${id} AND user_id = ${req.userId!}`;
    }

    return res.status(204).send();
  } catch (e: any) {
    return res.status(400).json({ error: e.message });
  }
});

router.delete('/:id', async (req: AuthRequest, res) => {
  try {
    await sql`DELETE FROM wishlist WHERE id = ${req.params.id} AND user_id = ${req.userId!}`;
    return res.status(204).send();
  } catch (e: any) {
    return res.status(400).json({ error: e.message });
  }
});

export default router;
