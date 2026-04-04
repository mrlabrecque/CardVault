import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import sql from '../db/db';

const router = Router();

router.use(requireAuth);

// GET /api/cards — list all cards for the authenticated user
router.get('/', async (req: AuthRequest, res) => {
  try {
    const cards = await sql`SELECT * FROM cards WHERE owner_id = ${req.userId!}`;
    return res.json(cards);
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

// GET /api/cards/:id
router.get('/:id', async (req: AuthRequest, res) => {
  try {
    const [card] = await sql`SELECT * FROM cards WHERE id = ${req.params.id} AND owner_id = ${req.userId!}`;
    if (!card) return res.status(404).json({ error: 'Not found' });
    return res.json(card);
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

// POST /api/cards
router.post('/', async (req: AuthRequest, res) => {
  try {
    const [card] = await sql`INSERT INTO cards ${sql({ ...req.body, owner_id: req.userId! })} RETURNING *`;
    return res.status(201).json(card);
  } catch (e: any) {
    return res.status(400).json({ error: e.message });
  }
});

// PATCH /api/cards/:id
router.patch('/:id', async (req: AuthRequest, res) => {
  try {
    const [card] = await sql`
      UPDATE cards SET ${sql(req.body)}
      WHERE id = ${req.params.id} AND owner_id = ${req.userId!}
      RETURNING *`;
    if (!card) return res.status(404).json({ error: 'Not found' });
    return res.json(card);
  } catch (e: any) {
    return res.status(400).json({ error: e.message });
  }
});

// DELETE /api/cards/:id
router.delete('/:id', async (req: AuthRequest, res) => {
  try {
    await sql`DELETE FROM cards WHERE id = ${req.params.id} AND owner_id = ${req.userId!}`;
    return res.status(204).send();
  } catch (e: any) {
    return res.status(400).json({ error: e.message });
  }
});

export default router;
