import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cardsightErrorResponse } from '../_shared/cardsight_fetch.ts';
import { fetchCardsightReleaseDetail } from '../_shared/cardsight_catalog_releases.ts';
import {
  ensureVaultReleaseForCardSight,
  upsertVaultSetsFromCatalog,
} from '../_shared/catalog_release_import.ts';
import {
  hydrateSetParallelsFromCardsight,
  HYDRATE_PARALLEL_DELAY_MS,
} from '../_shared/catalog_set_parallels.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Max-Age': '86400',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS, status: 200 });

  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) return json({ error: 'API key not configured' }, 500);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Missing authorization' }, 401);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: 'Unauthorized' }, 401);

  const { data: profile } = await supabase
    .from('profiles')
    .select('is_app_admin')
    .eq('id', user.id)
    .single();
  if (!profile?.is_app_admin) return json({ error: 'Forbidden' }, 403);

  try {
    const {
      cardsightReleaseId,
      releaseName,
      releaseYear,
      releaseSegmentId,
    } = await req.json() as {
      cardsightReleaseId: string;
      releaseName?: string;
      releaseYear?: string;
      releaseSegmentId?: string;
    };

    if (!cardsightReleaseId) {
      return json({ error: 'cardsightReleaseId is required' }, 400);
    }

    const releaseData = await fetchCardsightReleaseDetail(apiKey, cardsightReleaseId);
    const catalogSets = releaseData.sets ?? [];

    const releaseId = await ensureVaultReleaseForCardSight(
      supabase,
      cardsightReleaseId,
      releaseData,
      { releaseName, releaseYear, releaseSegmentId },
    );

    const dbSets = await upsertVaultSetsFromCatalog(supabase, releaseId, catalogSets);

    let setsWithParallels = 0;
    let parallelDefinitionsUpserted = 0;
    const parallelErrors: Array<{ setName: string; cardsightSetId: string; error: string }> = [];

    for (const set of dbSets) {
      const csSetId = set.cardsight_id?.trim();
      if (!csSetId) continue;

      try {
        const n = await hydrateSetParallelsFromCardsight(
          supabase,
          apiKey,
          set.id,
          csSetId,
        );
        parallelDefinitionsUpserted += n;
        setsWithParallels++;
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        parallelErrors.push({ setName: set.name, cardsightSetId: csSetId, error: msg });
        console.warn('[catalog-hydrate-release] parallel import failed', set.name, msg);
      }

      await new Promise((r) => setTimeout(r, HYDRATE_PARALLEL_DELAY_MS));
    }

    return json({
      releaseId,
      setsUpserted: dbSets.length,
      setsWithParallels,
      parallelDefinitionsUpserted,
      parallelErrors,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-hydrate-release]', msg);
    return cardsightErrorResponse(e, CORS);
  }
});
