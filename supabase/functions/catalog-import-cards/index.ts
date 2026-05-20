import { createClient } from 'jsr:@supabase/supabase-js@2';
import { cardsightErrorResponse } from '../_shared/cardsight_fetch.ts';
import {
  fetchAllCardsightReleaseCards,
  resolveBaseParallelId,
  upsertVaultSetCards,
} from '../_shared/catalog_import_cards.ts';
import {
  ensureSetParallelsFromCardsight,
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

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  try {
    const { cardsightReleaseId, cardsightSetId, setId, skipImages } = await req.json() as {
      cardsightReleaseId: string;
      cardsightSetId: string;
      setId?: string;
      /** When true (default), do not fetch CardSight images during import. */
      skipImages?: boolean;
    };

    if (!cardsightReleaseId || !cardsightSetId) {
      return json({ error: 'cardsightReleaseId and cardsightSetId are required' }, 400);
    }

    const allCards = await fetchAllCardsightReleaseCards(apiKey, cardsightReleaseId, {
      cardsightSetId,
    });

    if (allCards.length === 0) {
      return json({ imported: 0, total: 0, skipImages: skipImages !== false });
    }

    let dbSetId = setId;
    if (!dbSetId) {
      const { data: s } = await supabase
        .from('sets')
        .select('id')
        .eq('cardsight_id', cardsightSetId)
        .single();
      dbSetId = s?.id;
    }

    if (!dbSetId) {
      return json({ error: 'Set not found in DB. Import the set first via catalog-import-sets.' }, 400);
    }

    const { rows: parallelRows, importedFromCardsight: parallelsImported } =
      await ensureSetParallelsFromCardsight(supabase, apiKey, dbSetId, cardsightSetId);

    const baseParallelId = resolveBaseParallelId(parallelRows);

    // skipImages retained for API compatibility; images are never fetched here.
    void skipImages;

    const { imported, merged } = await upsertVaultSetCards(
      supabase,
      dbSetId,
      baseParallelId,
      allCards,
    );

    return json({
      imported,
      total: merged,
      parallelsImported,
      skipImages: true,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-import-cards]', msg);
    return cardsightErrorResponse(e, CORS);
  }
});
