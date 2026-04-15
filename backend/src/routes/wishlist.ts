import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import sql from '../db/db';

const router = Router();
router.use(requireAuth);

router.get('/', async (req: AuthRequest, res) => {
  try {
    const items = await sql`
      SELECT * FROM wishlist
      WHERE user_id = ${req.userId!}
      ORDER BY created_at DESC`;
    return res.json(items);
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

router.post('/', async (req: AuthRequest, res) => {
  const {
    player, year, set_name, parallel, card_number,
    is_rookie, is_auto, is_patch, serial_max, grade,
    ebay_query, target_price,
  } = req.body;

  try {
    const [item] = await sql`
      INSERT INTO wishlist (
        user_id, player, year, set_name, parallel, card_number,
        is_rookie, is_auto, is_patch, serial_max, grade,
        ebay_query, target_price, alert_status
      ) VALUES (
        ${req.userId!}, ${player ?? null}, ${year ?? null}, ${set_name ?? null},
        ${parallel ?? null}, ${card_number ?? null},
        ${is_rookie ?? false}, ${is_auto ?? false}, ${is_patch ?? false},
        ${serial_max ?? null}, ${grade ?? null},
        ${ebay_query ?? null}, ${target_price ?? null}, 'active'
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
    ebay_query, target_price, alert_status,
  } = req.body;

  // Build only the fields that were sent
  const updates: Record<string, any> = {};
  if ('player'       in req.body) updates.player       = player;
  if ('year'         in req.body) updates.year         = year;
  if ('set_name'     in req.body) updates.set_name     = set_name;
  if ('parallel'     in req.body) updates.parallel     = parallel;
  if ('card_number'  in req.body) updates.card_number  = card_number;
  if ('is_rookie'    in req.body) updates.is_rookie    = is_rookie;
  if ('is_auto'      in req.body) updates.is_auto      = is_auto;
  if ('is_patch'     in req.body) updates.is_patch     = is_patch;
  if ('serial_max'   in req.body) updates.serial_max   = serial_max;
  if ('grade'        in req.body) updates.grade        = grade;
  if ('ebay_query'   in req.body) updates.ebay_query   = ebay_query;
  if ('target_price' in req.body) updates.target_price = target_price;
  if ('alert_status' in req.body) updates.alert_status = alert_status;

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

router.delete('/:id', async (req: AuthRequest, res) => {
  try {
    await sql`DELETE FROM wishlist WHERE id = ${req.params.id} AND user_id = ${req.userId!}`;
    return res.status(204).send();
  } catch (e: any) {
    return res.status(400).json({ error: e.message });
  }
});

export default router;
