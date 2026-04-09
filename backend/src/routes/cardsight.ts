import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import {
  searchReleases,
  getReleaseDetails,
  getSetDetails,
  getSetCards,
  getCardImage,
  getSegment,
  mapSegmentToSport,
} from '../services/cardsight.service';
import { supabaseAdmin } from '../db/supabase';
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
  const { cardsightReleaseId, sport: sportParam, releaseType, ebaySearchTemplate } = req.body;
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
        ${releaseType ?? 'Hobby'},
        ${ebaySearchTemplate ?? '{year} {brand} {player_name} #{card_number} {parallel} {set} {auto} {patch} /{serial_max}'},
        ${slug},
        ${release.id}
      )
      ON CONFLICT (cardsight_id) DO UPDATE SET
        name = EXCLUDED.name,
        year = EXCLUDED.year,
        sport = COALESCE(releases.sport, EXCLUDED.sport),
        release_type = EXCLUDED.release_type,
        ebay_search_template = EXCLUDED.ebay_search_template
      RETURNING id, name
    `;

    // 5. Fetch full set details sequentially to avoid rate-limiting
    const setIds = (release.sets ?? []).map(s => s.id);
    const setDetails = [];
    for (let i = 0; i < setIds.length; i++) {
      if (i > 0) await delay(250);
      setDetails.push(await getSetDetails(setIds[i]));
    }

    // 6. Upsert each set, its parallels, and its cards
    let totalParallels = 0;
    let totalCards = 0;
    const CARD_PAGE_SIZE = 100;

    for (const set of setDetails) {
      const [dbSet] = await sql`
        INSERT INTO sets (release_id, name, card_count, cardsight_id)
        VALUES (${dbRelease.id}, ${set.name}, ${set.cardCount ?? null}, ${set.id})
        ON CONFLICT (cardsight_id) DO UPDATE SET
          name      = EXCLUDED.name,
          card_count = EXCLUDED.card_count
        RETURNING id
      `;

      // 6a. Upsert parallels
      const parallels = set.parallels ?? [];
      if (parallels.length > 0) {
        const rows = parallels.map((p, i) => ({
          set_id:       dbSet.id,
          name:         p.name,
          serial_max:   p.numberedTo ?? null,
          is_auto:      /\bauto(graph)?\b/i.test(p.name),
          color_hex:    null,
          sort_order:   i,
          cardsight_id: p.id,
        }));

        await sql`
          INSERT INTO set_parallels ${sql(rows)}
          ON CONFLICT (set_id, name) DO UPDATE SET
            serial_max   = EXCLUDED.serial_max,
            is_auto      = EXCLUDED.is_auto,
            cardsight_id = EXCLUDED.cardsight_id
        `;
        totalParallels += rows.length;
      }

      // 6b. Bulk-load all cards for this set (paginated)
      let skip = 0;
      while (true) {
        await delay(250);
        const page = await getSetCards(set.id, skip, CARD_PAGE_SIZE);
        if (page.cards.length === 0) break;

        const baseCards = page.cards.filter(c => !c.isParallelOnly);
        if (baseCards.length === 0) { skip += CARD_PAGE_SIZE; if (skip >= page.total_count) break; continue; }

        const cardRows = baseCards.map(c => {
          const attrs = c.attributes ?? [];
          return {
            set_id:            dbSet.id,
            player:            c.name,
            card_number:       c.number ?? null,
            serial_max:        null as number | null,
            is_rookie:         attrs.includes('RC'),
            is_auto:           attrs.includes('AU'),
            is_patch:          attrs.includes('GU'),
            is_ssp:            attrs.includes('SSP'),
            cardsight_card_id: c.id,
          };
        });

        // Deduplicate within the page — CardSight sometimes returns multiple
        // entries for the same player+number (photo/print variations). Merge
        // boolean flags with OR so e.g. the RC flag isn't lost if only one
        // of the duplicates carries it.
        const mergedMap = new Map<string, typeof cardRows[0]>();
        for (const r of cardRows) {
          const key = `${r.set_id}|${r.player}|${r.card_number ?? ''}`;
          const existing = mergedMap.get(key);
          if (existing) {
            existing.is_rookie = existing.is_rookie || r.is_rookie;
            existing.is_auto   = existing.is_auto   || r.is_auto;
            existing.is_patch  = existing.is_patch  || r.is_patch;
            existing.is_ssp    = existing.is_ssp    || r.is_ssp;
          } else {
            mergedMap.set(key, { ...r });
          }
        }
        const dedupedRows = Array.from(mergedMap.values());

        // Upsert on (set_id, player, card_number) — collapses CardSight duplicates.
        // card_number nullable requires two separate statements.
        const withNumber    = dedupedRows.filter(r => r.card_number !== null);
        const withoutNumber = dedupedRows.filter(r => r.card_number === null);

        if (withNumber.length > 0) {
          await sql`
            INSERT INTO master_card_definitions ${sql(withNumber)}
            ON CONFLICT (set_id, player, card_number) WHERE card_number IS NOT NULL
            DO UPDATE SET
              cardsight_card_id = EXCLUDED.cardsight_card_id,
              is_rookie = master_card_definitions.is_rookie OR EXCLUDED.is_rookie,
              is_auto   = master_card_definitions.is_auto   OR EXCLUDED.is_auto,
              is_patch  = master_card_definitions.is_patch  OR EXCLUDED.is_patch,
              is_ssp    = master_card_definitions.is_ssp    OR EXCLUDED.is_ssp
          `;
        }

        if (withoutNumber.length > 0) {
          await sql`
            INSERT INTO master_card_definitions ${sql(withoutNumber)}
            ON CONFLICT (set_id, player) WHERE card_number IS NULL
            DO UPDATE SET
              cardsight_card_id = EXCLUDED.cardsight_card_id,
              is_rookie = master_card_definitions.is_rookie OR EXCLUDED.is_rookie,
              is_auto   = master_card_definitions.is_auto   OR EXCLUDED.is_auto,
              is_patch  = master_card_definitions.is_patch  OR EXCLUDED.is_patch,
              is_ssp    = master_card_definitions.is_ssp    OR EXCLUDED.is_ssp
          `;
        }

        totalCards += baseCards.length;
        skip += CARD_PAGE_SIZE;
        if (skip >= page.total_count) break;
      }
    }

    return res.json({
      releaseId:      dbRelease.id,
      releaseName:    dbRelease.name,
      setsCount:      setDetails.length,
      parallelsCount: totalParallels,
      cardsCount:     totalCards,
    });
  } catch (e: any) {
    console.error('[cardsight/import]', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// POST /api/cardsight/cards/:masterCardId/image
// Lazily fetches the card image from CardSight, stores it in Supabase Storage,
// and writes the public URL back to master_card_definitions.image_url.
// Safe to call multiple times — returns immediately if image already cached.
router.post('/cards/:masterCardId/image', async (req: AuthRequest, res) => {
  const { masterCardId } = req.params;

  try {
    const [master] = await sql<{ cardsight_card_id: string | null; image_url: string | null }[]>`
      SELECT cardsight_card_id, image_url
      FROM master_card_definitions
      WHERE id = ${masterCardId}
    `;
    if (!master) return res.status(404).json({ error: 'Card not found' });

    // Already cached — return immediately
    if (master.image_url) return res.json({ image_url: master.image_url });

    // Manual entry with no CardSight ID — no image available
    if (!master.cardsight_card_id) return res.json({ image_url: null });

    const imageBuffer = await getCardImage(master.cardsight_card_id);

    const storagePath = `cards/${master.cardsight_card_id}.jpg`;
    const { error: uploadError } = await supabaseAdmin.storage
      .from('card-images')
      .upload(storagePath, imageBuffer, { contentType: 'image/jpeg', upsert: true });

    if (uploadError) throw new Error(`Storage upload failed: ${uploadError.message}`);

    const { data: { publicUrl } } = supabaseAdmin.storage
      .from('card-images')
      .getPublicUrl(storagePath);

    await sql`
      UPDATE master_card_definitions
      SET image_url = ${publicUrl}
      WHERE id = ${masterCardId}
    `;

    return res.json({ image_url: publicUrl });
  } catch (e: any) {
    console.error('[cardsight/cards/image]', e.message);
    return res.status(500).json({ error: e.message });
  }
});

export default router;
