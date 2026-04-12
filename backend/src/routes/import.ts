import { Router, Response } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { supabaseAdmin } from '../db/supabase';

const router = Router();
router.use(requireAuth);

/**
 * POST /api/import
 *
 * Bulk collection importer. Accepts a resolved payload from the frontend wizard
 * and performs all DB writes server-side in batches.
 *
 * Body shape:
 * {
 *   releases: ResolvedRelease[]   // releases to upsert (matched or new)
 *   cards: ImportCard[]           // one entry per physical card to import
 * }
 *
 * ResolvedRelease:
 * {
 *   tempId: string               // client-side key used in cards[] to reference this release
 *   existingReleaseId?: string   // if matched to existing DB release — skip upsert
 *   existingSetId?: string       // if matched to existing DB set — skip upsert
 *   releaseName: string
 *   releaseYear: number
 *   sport: string
 *   releaseType: string          // e.g. "hobby", "retail", "unknown"
 *   setName: string              // e.g. "Base Set", "Refractors"
 * }
 *
 * ImportCard:
 * {
 *   releaseTempId: string        // references ResolvedRelease.tempId
 *   existingMasterCardId?: string // if matched to existing master_card_definition
 *   player: string
 *   cardNumber?: string
 *   isRookie: boolean
 *   isAuto: boolean
 *   isPatch: boolean
 *   serialMax?: number
 *   parallelName: string         // "Base" if not specified
 *   pricePaid: number
 *   serialNumber?: string
 *   isGraded: boolean
 *   grader?: string
 *   gradeValue?: string
 * }
 */
router.post('/', async (req: AuthRequest, res: Response) => {
  const userId = req.userId!;
  const { releases: resolvedReleases, cards: importCards } = req.body;

  if (!Array.isArray(resolvedReleases) || !Array.isArray(importCards)) {
    return res.status(400).json({ error: 'releases and cards arrays are required' });
  }
  if (importCards.length === 0) {
    return res.status(400).json({ error: 'No cards to import' });
  }

  try {
    // ── Step 1: Upsert releases ───────────────────────────────────────────────
    // Map from client tempId → { releaseId, setId }
    const releaseMap = new Map<string, { releaseId: string; setId: string }>();

    for (const rel of resolvedReleases) {
      let releaseId: string;
      let setId: string;

      if (rel.existingReleaseId && rel.existingSetId) {
        // Already matched to existing records — no DB write needed
        releaseId = rel.existingReleaseId;
        setId = rel.existingSetId;
      } else if (rel.existingReleaseId && !rel.existingSetId) {
        // Release matched, but set is new under it
        releaseId = rel.existingReleaseId;

        const { data: newSet, error: setErr } = await supabaseAdmin
          .from('sets')
          .insert({
            release_id: releaseId,
            name: rel.setName,
            prefix: null,
            source: 'import',
          })
          .select('id')
          .single();

        if (setErr) throw new Error(`Failed to create set "${rel.setName}": ${setErr.message}`);
        setId = newSet.id;
      } else {
        // Both release and set are new — build a slug and insert.
        // Append a short random suffix so re-imports never collide with existing slugs.
        const baseSlug = [rel.releaseYear, rel.releaseName, rel.sport]
          .join(' ')
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, '-')
          .replace(/^-+|-+$/g, '');
        const slug = `${baseSlug}-${Math.random().toString(36).slice(2, 7)}`;

        const { data: newRelease, error: releaseErr } = await supabaseAdmin
          .from('releases')
          .insert({
            name: rel.releaseName,
            year: rel.releaseYear,
            sport: rel.sport,
            release_type: rel.releaseType || 'Unknown',
            ebay_search_template: '{year} {brand} {set} {player_name} #{card_number}',
            set_slug: slug,
            source: 'import',
          })
          .select('id')
          .single();

        if (releaseErr) throw new Error(`Failed to create release "${rel.releaseName}": ${releaseErr.message}`);
        releaseId = newRelease.id;

        const { data: newSet, error: setErr } = await supabaseAdmin
          .from('sets')
          .insert({
            release_id: releaseId,
            name: rel.setName,
            prefix: null,
            source: 'import',
          })
          .select('id')
          .single();

        if (setErr) throw new Error(`Failed to create set "${rel.setName}": ${setErr.message}`);
        setId = newSet.id;
      }

      releaseMap.set(rel.tempId, { releaseId, setId });
    }

    // ── Step 2: Batch-insert user_cards ──────────────────────────────────────
    // master_card_id is intentionally null for all import rows — the catalog
    // (master_card_definitions) stays clean (CardSight-only). Card metadata
    // is stored denormalized directly on user_cards instead.
    // set_id is written so the eBay comps query can resolve the release template.
    const userCardRows = importCards.map((card: any) => ({
      master_card_id: null,
      set_id: releaseMap.get(card.releaseTempId)?.setId ?? null,
      user_id: userId,
      player: card.player,
      card_number: card.cardNumber || null,
      is_rookie: card.isRookie || false,
      is_auto: card.isAuto || false,
      is_patch: card.isPatch || false,
      parallel_id: null,
      parallel_name: card.parallelName || 'Base',
      price_paid: card.pricePaid ?? null,
      serial_number: card.serialNumber || null,
      is_graded: card.isGraded || false,
      grader: card.grader || null,
      grade_value: card.gradeValue || null,
    }));

    // Insert in chunks of 500 to stay within Supabase request limits
    const CHUNK = 500;
    let inserted = 0;
    for (let offset = 0; offset < userCardRows.length; offset += CHUNK) {
      const chunk = userCardRows.slice(offset, offset + CHUNK);
      const { error: insertErr } = await supabaseAdmin.from('user_cards').insert(chunk);
      if (insertErr) throw new Error(`Failed to insert user cards (offset ${offset}): ${insertErr.message}`);
      inserted += chunk.length;
    }

    return res.json({
      success: true,
      inserted,
      releasesCreated: resolvedReleases.filter((r: any) => !r.existingReleaseId).length,
      setsCreated: resolvedReleases.filter((r: any) => !r.existingSetId).length,
    });
  } catch (e: any) {
    console.error('[import]', e.message);
    return res.status(500).json({ error: e.message });
  }
});

export default router;
