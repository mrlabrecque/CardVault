import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import sql from '../db/db';

const router = Router();
router.use(requireAuth);

router.get('/', async (req: AuthRequest, res) => {
  try {
    const items = await sql`SELECT * FROM wishlist WHERE user_id = ${req.userId!}`;
    return res.json(items);
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

router.post('/', async (req: AuthRequest, res) => {
  try {
    const [item] = await sql`
      INSERT INTO wishlist ${sql({ ...req.body, user_id: req.userId!, alert_status: 'active' })}
      RETURNING *`;
    return res.status(201).json(item);
  } catch (e: any) {
    return res.status(400).json({ error: e.message });
  }
});

router.patch('/:id', async (req: AuthRequest, res) => {
  try {
    const [item] = await sql`
      UPDATE wishlist SET ${sql(req.body)}
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
