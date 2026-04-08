import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import {
  searchReleases,
  getReleaseDetails,
  getSetDetails,
  getSegment,
  mapSegmentToSport,
} from '../services/cardsight.service';
import sql from '../db/db';

const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

const router = Router();
router.use(requireAuth);

// GET /api/cardsight/search?year=2023&manufacturer=Topps&segment=Baseball
router.get('/search', async (req: AuthRequest, res) => {
  const { year, manufacturer, segment } = req.query;

  try {
    const releases = await searchReleases({
      year:         year         ? parseInt(year as string, 10) : undefined,
      manufacturer: manufacturer ? (manufacturer as string)     : undefined,
      segment:      segment      ? (segment as string)          : undefined,
    });
    return res.json(releases);
  } catch (e: any) {
    console.error('[cardsight/search]', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// POST /api/cardsight/import
// body: { cardsightReleaseId: string }
router.post('/import', async (req: AuthRequest, res) => {
  const { cardsightReleaseId, sport: sportParam } = req.body;
  if (!cardsightReleaseId) return res.status(400).json({ error: 'cardsightReleaseId is required' });

  try {
    // 1. Fetch release details — includes embedded set summaries
    const release = await getReleaseDetails(cardsightReleaseId);

    // 2. Sport comes from the search segment the user filtered by.
    //    Fall back to segment ID lookup only if not provided.
    let sport: string | null = sportParam ?? null;
    if (!sport) {
      try {
        const segment = await getSegment(release.segmentId);
        sport = mapSegmentToSport(segment.name);
      } catch (e: any) {
        console.warn('[cardsight/import] segment lookup failed:', e.message);
      }
    }

    // 3. Build slug
    const slug = [release.year, release.name, sport ?? '']
      .map(v => String(v).toLowerCase().trim().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''))
      .filter(Boolean)
      .join('-');

    // 4. Upsert release — ON CONFLICT (cardsight_id) preserves any admin edits to sport
    //    (COALESCE keeps existing sport if already set, only fills in when null)
    const [dbRelease] = await sql`
      INSERT INTO releases (name, year, sport, release_type, ebay_search_template, set_slug, cardsight_id)
      VALUES (
        ${release.name},
        ${parseInt(release.year, 10)},
        ${sport},
        ${'Hobby'},
        ${'{year} {brand} #{card_number} {player_name}'},
        ${slug},
        ${release.id}
      )
      ON CONFLICT (cardsight_id) DO UPDATE SET
        name = EXCLUDED.name,
        year = EXCLUDED.year,
        sport = COALESCE(releases.sport, EXCLUDED.sport)
      RETURNING id, name
    `;

    // 5. Fetch full set details sequentially to avoid rate-limiting
    const setIds = (release.sets ?? []).map(s => s.id);
    const setDetails = [];
    for (let i = 0; i < setIds.length; i++) {
      if (i > 0) await delay(250);
      setDetails.push(await getSetDetails(setIds[i]));
    }

    // 6. Upsert each set and its parallels
    let totalParallels = 0;

    for (const set of setDetails) {
      const [dbSet] = await sql`
        INSERT INTO sets (release_id, name, card_count, cardsight_id)
        VALUES (${dbRelease.id}, ${set.name}, ${set.cardCount ?? null}, ${set.id})
        ON CONFLICT (cardsight_id) DO UPDATE SET
          name      = EXCLUDED.name,
          card_count = EXCLUDED.card_count
        RETURNING id
      `;

      const parallels = set.parallels ?? [];
      if (parallels.length === 0) continue;

      const rows = parallels.map((p, i) => ({
        set_id:       dbSet.id,
        name:         p.name,
        serial_max:   p.numberedTo ?? null,
        is_auto:      /\bauto(graph)?\b/i.test(p.name),
        color_hex:    null,
        sort_order:   i,
        cardsight_id: p.id,
      }));

      // Upsert on (set_id, name) — the existing unique constraint.
      // cardsight_id gets backfilled on re-import.
      await sql`
        INSERT INTO set_parallels ${sql(rows)}
        ON CONFLICT (set_id, name) DO UPDATE SET
          serial_max   = EXCLUDED.serial_max,
          is_auto      = EXCLUDED.is_auto,
          cardsight_id = EXCLUDED.cardsight_id
      `;
      totalParallels += rows.length;
    }

    return res.json({
      releaseId:      dbRelease.id,
      releaseName:    dbRelease.name,
      setsCount:      setDetails.length,
      parallelsCount: totalParallels,
    });
  } catch (e: any) {
    console.error('[cardsight/import]', e.message);
    return res.status(500).json({ error: e.message });
  }
});

export default router;
