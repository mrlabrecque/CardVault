import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { createListing } from '../services/ebay.service';
import sql from '../db/db';

const router = Router();
router.use(requireAuth);

// POST /api/ebay/list/:cardId — post a card to eBay
router.post('/list/:cardId', async (req: AuthRequest, res) => {
  try {
    const [card] = await sql`SELECT * FROM cards WHERE id = ${req.params.cardId} AND owner_id = ${req.userId!}`;
    if (!card) return res.status(404).json({ error: 'Card not found' });

    const listing = await createListing(card);
    return res.json(listing);
  } catch (e: any) {
    return res.status(500).json({ error: e.message });
  }
});

export default router;
