import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { searchSoldListings } from '../services/ebay.service';
import sql from '../db/db';

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

export default router;
