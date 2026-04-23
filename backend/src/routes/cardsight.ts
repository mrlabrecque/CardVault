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
  identifyCard,
  CardsightDetection,
} from '../services/cardsight.service';
import express from 'express';
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

// GET /api/cardsight/releases/:cardsightReleaseId/sets
// Returns set summaries for a catalog release without importing anything. 1 external API call.
router.get('/releases/:cardsightReleaseId/sets', async (req: AuthRequest, res) => {
  const { cardsightReleaseId } = req.params;
  try {
    const release = await getReleaseDetails(cardsightReleaseId);
    return res.json(release.sets ?? []);
  } catch (e: any) {
    console.error('[cardsight/releases/sets]', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// POST /api/cardsight/lazy-import
// Imports a single release + single set (with its parallels). ~1 external API call.
// Release metadata is passed from the client (already known from search results) to
// avoid a redundant getReleaseDetails call.
router.post('/lazy-import', async (req: AuthRequest, res) => {
  const { cardsightReleaseId, releaseName, releaseYear, releaseSegmentId, cardsightSetId } = req.body;
  if (!cardsightReleaseId || !releaseName || !releaseYear || !cardsightSetId) {
    return res.status(400).json({ error: 'cardsightReleaseId, releaseName, releaseYear, and cardsightSetId are required' });
  }
  try {
    const sport = releaseSegmentId ? mapSegmentToSport(String(releaseSegmentId)) : null;
    const slug = [releaseYear, releaseName, sport ?? '']
      .map(v => String(v).toLowerCase().trim().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''))
      .filter(Boolean)
      .join('-');

    const [dbRelease] = await sql`
      INSERT INTO releases (name, year, sport, release_type, set_slug, cardsight_id)
      VALUES (${releaseName}, ${parseInt(String(releaseYear), 10)}, ${sport}, ${'Hobby'}, ${slug}, ${cardsightReleaseId})
      ON CONFLICT (cardsight_id) DO UPDATE SET
        name  = EXCLUDED.name,
        year  = EXCLUDED.year,
        sport = COALESCE(releases.sport, EXCLUDED.sport)
      RETURNING id, name, sport
    `;

    const setDetail = await getSetDetails(cardsightSetId);

    const [dbSet] = await sql`
      INSERT INTO sets (release_id, name, card_count, cardsight_id)
      VALUES (${dbRelease.id}, ${setDetail.name}, ${setDetail.cardCount ?? null}, ${setDetail.id})
      ON CONFLICT (cardsight_id) DO UPDATE SET
        name       = EXCLUDED.name,
        card_count = EXCLUDED.card_count
      RETURNING id, name
    `;

    const parallels = setDetail.parallels ?? [];
    let dbParallels: any[] = [];
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
      dbParallels = await sql`
        INSERT INTO set_parallels ${sql(rows)}
        ON CONFLICT (set_id, name) DO UPDATE SET
          serial_max   = EXCLUDED.serial_max,
          is_auto      = EXCLUDED.is_auto,
          cardsight_id = EXCLUDED.cardsight_id
        RETURNING id, set_id, name, serial_max, is_auto, color_hex, sort_order, created_at
      `;
    }

    return res.json({
      releaseId:    dbRelease.id,
      releaseName:  dbRelease.name,
      releaseSport: dbRelease.sport,
      setId:        dbSet.id,
      setName:      dbSet.name,
      parallels:    dbParallels,
    });
  } catch (e: any) {
    console.error('[cardsight/lazy-import]', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// POST /api/cardsight/import
// body: { cardsightReleaseId: string }
router.post('/import', async (req: AuthRequest, res) => {
  const { cardsightReleaseId, sport: sportParam, releaseType } = req.body;
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
      INSERT INTO releases (name, year, sport, release_type, set_slug, cardsight_id)
      VALUES (
        ${release.name},
        ${parseInt(release.year, 10)},
        ${sport},
        ${releaseType ?? 'Hobby'},
        ${slug},
        ${release.id}
      )
      ON CONFLICT (cardsight_id) DO UPDATE SET
        name = EXCLUDED.name,
        year = EXCLUDED.year,
        sport = COALESCE(releases.sport, EXCLUDED.sport),
        release_type = EXCLUDED.release_type
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
    const [master] = await sql<{
      cardsight_card_id: string | null;
      image_url: string | null;
      player: string | null;
      card_number: string | null;
      set_cardsight_id: string | null;
    }[]>`
      SELECT
        mcd.cardsight_card_id,
        mcd.image_url,
        mcd.player,
        mcd.card_number,
        s.cardsight_id AS set_cardsight_id
      FROM master_card_definitions mcd
      LEFT JOIN sets s ON s.id = mcd.set_id
      WHERE mcd.id = ${masterCardId}
    `;
    if (!master) return res.status(404).json({ error: 'Card not found' });

    console.log(`[cardsight/image] masterCardId=${masterCardId} cardsight_card_id=${master.cardsight_card_id} image_url=${master.image_url} set_cardsight_id=${master.set_cardsight_id} player=${master.player}`);

    // Already cached — return immediately
    if (master.image_url) return res.json({ image_url: master.image_url });

    // No CardSight card ID yet — try to find it by searching the set's cards on CardSight
    if (!master.cardsight_card_id) {
      if (!master.set_cardsight_id || !master.player) {
        console.log(`[cardsight/image] no cardsight_card_id and missing set_cardsight_id or player — skipping`);
        return res.json({ image_url: null });
      }

      // Page through CardSight cards for this set looking for player + card_number match
      let found: string | null = null;
      let skip = 0;
      const take = 100;
      const playerLower = master.player.toLowerCase();
      const cardNum = master.card_number ?? null;

      outer: while (true) {
        const { cards, total_count } = await getSetCards(master.set_cardsight_id, skip, take);
        for (const c of cards) {
          if (c.isParallelOnly) continue;
          const nameMatch = c.name.toLowerCase().includes(playerLower) || playerLower.includes(c.name.toLowerCase());
          const numMatch = !cardNum || !c.number || c.number === cardNum;
          if (nameMatch && numMatch) { found = c.id; break outer; }
        }
        skip += take;
        if (skip >= total_count || cards.length === 0) break;
      }

      if (!found) {
        console.log(`[cardsight/image] no match found in CardSight for player="${master.player}" card_number="${master.card_number}" set_cardsight_id=${master.set_cardsight_id}`);
        return res.json({ image_url: null });
      }
      console.log(`[cardsight/image] found cardsight_card_id=${found} for player="${master.player}"`);

      // Cache the discovered CardSight ID for future calls
      await sql`UPDATE master_card_definitions SET cardsight_card_id = ${found} WHERE id = ${masterCardId}`;
      master.cardsight_card_id = found;
    }

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
    if (e.message?.includes('404')) {
      console.warn(`[cardsight/cards/image] no image available for masterCardId=${masterCardId}`);
      return res.json({ image_url: null });
    }
    console.error('[cardsight/cards/image]', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// POST /api/cardsight/identify
// Body: raw image binary (image/jpeg, image/png, image/webp)
// Query: ?segment=baseball|football|basketball|hockey (optional)
router.post(
  '/identify',
  express.raw({ type: ['image/jpeg', 'image/png', 'image/webp', 'image/heif', 'image/heic'], limit: '20mb' }),
  async (req: AuthRequest, res) => {
    const mimeType = (req.headers['content-type'] ?? 'image/jpeg').split(';')[0].trim();
    const segment = req.query['segment'] as string | undefined;

    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      return res.status(400).json({ error: 'Image body is required' });
    }

    try {
      const buf = req.body as Buffer;
      const result = await identifyCard(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer, mimeType, segment);

      if (!result.success || !result.detections?.length) {
        return res.json({ success: false, detections: [] });
      }

      const best: CardsightDetection = result.detections[0];
      const card = best.card;

      // DB lookups for the scanner staging flow
      let masterCardId: string | null = null;
      let masterCardPlayer: string | null = null;
      let masterCardNumber: string | null = null;
      let parallelId: string | null = null;
      let parallelName: string = best.card.parallel?.name ?? 'Base';
      let setParallels: any[] = [];

      if (card.id) {
        const [dbCard] = await sql<{ id: string; player: string; card_number: string | null }[]>`
          SELECT id, player, card_number FROM master_card_definitions
          WHERE cardsight_card_id = ${card.id} LIMIT 1
        `;
        if (dbCard) {
          masterCardId    = dbCard.id;
          masterCardPlayer = dbCard.player;
          masterCardNumber = dbCard.card_number;
        }
      }

      if (card.parallel?.id) {
        const [dbParallel] = await sql<{ id: string; name: string }[]>`
          SELECT id, name FROM set_parallels WHERE cardsight_id = ${card.parallel.id} LIMIT 1
        `;
        if (dbParallel) {
          parallelId   = dbParallel.id;
          parallelName = dbParallel.name;
        }
      }

      if (card.setId) {
        setParallels = await sql<any[]>`
          SELECT sp.id, sp.name, sp.serial_max, sp.is_auto, sp.color_hex, sp.sort_order
          FROM set_parallels sp
          JOIN sets s ON s.id = sp.set_id
          WHERE s.cardsight_id = ${card.setId}
          ORDER BY sp.sort_order ASC
        `;
      }

      // Build eBay suggested query
      const parts: string[] = [];
      if (masterCardPlayer ?? card.name) parts.push(masterCardPlayer ?? card.name!);
      if (card.year)        parts.push(card.year);
      if (card.releaseName) parts.push(card.releaseName);
      if (parallelName && parallelName.toLowerCase() !== 'base') parts.push(parallelName);
      if (best.grading?.company?.name) parts.push(best.grading.company.name);

      return res.json({
        success: true,
        detections: result.detections,
        suggestedQuery: parts.join(' '),
        processingTime: result.processingTime,
        masterCardId,
        masterCardPlayer,
        masterCardNumber,
        parallelId,
        parallelName,
        setParallels,
      });
    } catch (e: any) {
      console.error('[cardsight/identify]', e.message);
      return res.status(500).json({ error: e.message });
    }
  },
);

export default router;
