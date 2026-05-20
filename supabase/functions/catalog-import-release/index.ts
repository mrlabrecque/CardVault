import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cardsightErrorResponse } from '../_shared/cardsight_fetch.ts';
import { fetchCardsightReleaseDetail } from '../_shared/cardsight_catalog_releases.ts';
import {
  ensureVaultReleaseForCardSight,
  upsertVaultSetsFromCatalog,
  type VaultSetRow,
} from '../_shared/catalog_release_import.ts';
import {
  CARDSIGHT_CARDS_PAGE_DELAY_MS,
  fetchAllCardsightReleaseCards,
  groupCardsByCardsightSetId,
  resolveBaseParallelId,
  upsertVaultSetCards,
} from '../_shared/catalog_import_cards.ts';
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

async function requireAppAdmin(
  req: Request,
  supabase: ReturnType<typeof createClient>,
): Promise<{ userId: string } | Response> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Missing authorization' }, 401);

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

  return { userId: user.id };
}

async function importCardsPerSet(
  apiKey: string,
  cardsightReleaseId: string,
  dbSets: VaultSetRow[],
  baseParallelBySetId: Map<string, string>,
  supabase: ReturnType<typeof createClient>,
): Promise<{
  cardsImported: number;
  setCardsMerged: number;
  cardErrors: Array<{ setName: string; error: string }>;
}> {
  let cardsImported = 0;
  let setCardsMerged = 0;
  const cardErrors: Array<{ setName: string; error: string }> = [];

  for (const set of dbSets) {
    const csSetId = set.cardsight_id?.trim();
    const baseParallelId = baseParallelBySetId.get(set.id);
    if (!csSetId || !baseParallelId) continue;

    try {
      const raw = await fetchAllCardsightReleaseCards(apiKey, cardsightReleaseId, {
        cardsightSetId: csSetId,
      });
      const result = await upsertVaultSetCards(supabase, set.id, baseParallelId, raw);
      cardsImported += result.imported;
      setCardsMerged += result.merged;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      cardErrors.push({ setName: set.name, error: msg });
      console.warn('[catalog-import-release] cards failed', set.name, msg);
    }

    await new Promise((r) => setTimeout(r, CARDSIGHT_CARDS_PAGE_DELAY_MS));
  }

  return { cardsImported, setCardsMerged, cardErrors };
}

async function importCardsReleaseWide(
  apiKey: string,
  cardsightReleaseId: string,
  dbSets: VaultSetRow[],
  baseParallelBySetId: Map<string, string>,
  supabase: ReturnType<typeof createClient>,
): Promise<{
  cardsImported: number;
  setCardsMerged: number;
  cardErrors: Array<{ setName: string; error: string }>;
}> {
  const allRaw = await fetchAllCardsightReleaseCards(apiKey, cardsightReleaseId);
  const grouped = groupCardsByCardsightSetId(allRaw);
  const hasSetIds = grouped.size > 0;

  if (!hasSetIds) {
    return importCardsPerSet(
      apiKey,
      cardsightReleaseId,
      dbSets,
      baseParallelBySetId,
      supabase,
    );
  }

  let cardsImported = 0;
  let setCardsMerged = 0;
  const cardErrors: Array<{ setName: string; error: string }> = [];

  for (const set of dbSets) {
    const csSetId = set.cardsight_id?.trim();
    const baseParallelId = baseParallelBySetId.get(set.id);
    if (!csSetId || !baseParallelId) continue;

    try {
      const raw = grouped.get(csSetId) ?? [];
      const result = await upsertVaultSetCards(supabase, set.id, baseParallelId, raw);
      cardsImported += result.imported;
      setCardsMerged += result.merged;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      cardErrors.push({ setName: set.name, error: msg });
    }
  }

  return { cardsImported, setCardsMerged, cardErrors };
}

// Re-export for parallel lookup after hydrate
async function loadParallels(
  supabase: ReturnType<typeof createClient>,
  setId: string,
) {
  const { data, error } = await supabase
    .from('set_parallels')
    .select('id, name, sort_order')
    .eq('set_id', setId);
  if (error) throw new Error(error.message);
  return (data ?? []) as { id: string; name: string; sort_order: number | null }[];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS, status: 200 });

  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) return json({ error: 'API key not configured' }, 500);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const auth = await requireAppAdmin(req, supabase);
  if (auth instanceof Response) return auth;

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
    const baseParallelBySetId = new Map<string, string>();

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
        const rows = await loadParallels(supabase, set.id);
        baseParallelBySetId.set(set.id, resolveBaseParallelId(rows));
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        parallelErrors.push({ setName: set.name, cardsightSetId: csSetId, error: msg });
      }

      await new Promise((r) => setTimeout(r, HYDRATE_PARALLEL_DELAY_MS));
    }

    const { cardsImported, setCardsMerged, cardErrors } = await importCardsReleaseWide(
      apiKey,
      cardsightReleaseId,
      dbSets,
      baseParallelBySetId,
      supabase,
    );

    return json({
      releaseId,
      setsUpserted: dbSets.length,
      setsWithParallels,
      parallelDefinitionsUpserted,
      parallelErrors,
      cardsImported,
      setCardsMerged,
      cardErrors,
      skipImages: true,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-import-release]', msg);
    return cardsightErrorResponse(e, CORS);
  }
});
