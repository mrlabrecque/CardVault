import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  fetchCardsightReleaseDetail,
  type CardSightReleaseSetSummary,
} from '../_shared/cardsight_catalog_releases.ts';
import {
  ensureVaultReleaseForCardSight,
  upsertVaultSetsFromCatalog,
} from '../_shared/catalog_release_import.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function mapSetSummaries(sets: CardSightReleaseSetSummary[]) {
  return sets.map((s) => ({
    cardsightId: s.id,
    name: s.name,
    cardCount: s.cardCount ?? null,
    parallelCount: s.parallelCount ?? 0,
  }));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) return json({ error: 'API key not configured' }, 500);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  try {
    const {
      cardsightReleaseId,
      releaseName,
      releaseYear,
      releaseSegmentId,
      metaOnly,
    } = await req.json() as {
      cardsightReleaseId: string;
      releaseName?: string;
      releaseYear?: string;
      releaseSegmentId?: string;
      metaOnly?: boolean;
    };

    if (!cardsightReleaseId) {
      return json({ error: 'cardsightReleaseId is required' }, 400);
    }

    const releaseData = await fetchCardsightReleaseDetail(apiKey, cardsightReleaseId);
    const catalogSets = releaseData.sets ?? [];

    if (metaOnly) {
      return json({ sets: mapSetSummaries(catalogSets) });
    }

    const releaseId = await ensureVaultReleaseForCardSight(
      supabase,
      cardsightReleaseId,
      releaseData,
      { releaseName, releaseYear, releaseSegmentId },
    );

    const dbSets = await upsertVaultSetsFromCatalog(supabase, releaseId, catalogSets);

    return json({
      sets: dbSets.map((s) => ({
        id: s.id,
        name: s.name,
        cardCount: s.card_count,
        cardsightId: s.cardsight_id,
        parallelCount: s.cardsight_parallel_count ?? 0,
      })),
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-import-sets]', msg);
    return json({ error: msg }, 500);
  }
});
