import { createClient } from 'jsr:@supabase/supabase-js@2';

const CARDSIGHT_BASE = 'https://api.cardsight.ai';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SEGMENT_TO_SPORT: Record<string, string> = {
  baseball: 'Baseball', mlb: 'Baseball',
  basketball: 'Basketball', nba: 'Basketball',
  football: 'Football', nfl: 'Football',
  soccer: 'Soccer', mls: 'Soccer',
  hockey: 'Hockey', nhl: 'Hockey',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
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
    } = await req.json() as {
      cardsightReleaseId: string;
      releaseName?: string;
      releaseYear?: string;
      releaseSegmentId?: string;
    };

    if (!cardsightReleaseId) {
      return json({ error: 'cardsightReleaseId is required' }, 400);
    }

    // Fetch release details from CardSight — returns embedded set summaries
    const csRes = await fetch(`${CARDSIGHT_BASE}/v1/catalog/releases/${cardsightReleaseId}`, {
      headers: { 'X-API-Key': apiKey },
    });
    if (!csRes.ok) throw new Error(`CardSight release fetch failed: ${csRes.status}`);

    const releaseData = await csRes.json() as {
      id: string;
      name: string;
      year: string;
      segmentId?: string;
      sets?: Array<{ id: string; name: string; cardCount?: number }>;
    };

    const sets = releaseData.sets ?? [];

    // Find or upsert the release shell in DB
    const { data: existingRelease } = await supabase
      .from('releases')
      .select('id')
      .eq('cardsight_id', cardsightReleaseId)
      .maybeSingle();

    let releaseId: string;

    if (existingRelease) {
      releaseId = existingRelease.id as string;
    } else {
      // Fallback: create shell if caller provided metadata
      const name = releaseName ?? releaseData.name;
      const year = releaseYear ?? releaseData.year;
      const segId = releaseSegmentId ?? releaseData.segmentId ?? '';
      const sport = SEGMENT_TO_SPORT[String(segId).toLowerCase()] ?? 'Unknown';
      const slug = [year, name, sport]
        .map(v => String(v).toLowerCase().trim().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''))
        .filter(Boolean)
        .join('-');

      const { data, error } = await supabase
        .from('releases')
        .insert({
          name, year: parseInt(String(year), 10), sport,
          release_type: 'Hobby', set_slug: slug, cardsight_id: cardsightReleaseId,
        })
        .select('id')
        .single();

      if (error && error.code === '23505') {
        const { data: raceWinner } = await supabase
          .from('releases').select('id').eq('cardsight_id', cardsightReleaseId).single();
        releaseId = (raceWinner as { id: string }).id;
      } else if (error) {
        throw new Error(error.message);
      } else {
        releaseId = (data as { id: string }).id;
      }
    }

    if (sets.length === 0) return json({ sets: [] });

    // Deduplicate sets by (release_id, name) to avoid upsert conflicts
    const setMap = new Map<string, { release_id: string; name: string; card_count: number | null; cardsight_id: string }>();
    for (const s of sets) {
      const key = `${releaseId}|${s.name}`;
      if (!setMap.has(key)) {
        setMap.set(key, {
          release_id: releaseId,
          name: s.name,
          card_count: s.cardCount ?? null,
          cardsight_id: s.id,
        });
      }
    }
    const setRows = Array.from(setMap.values());

    const { data: dbSets, error: setsError } = await supabase
      .from('sets')
      .upsert(setRows, { onConflict: 'release_id,name' })
      .select('id, name, card_count, cardsight_id');

    if (setsError) throw new Error(setsError.message);

    return json({
      sets: ((dbSets ?? []) as Array<{ id: string; name: string; card_count: number | null; cardsight_id: string }>).map(s => ({
        id:          s.id,
        name:        s.name,
        cardCount:   s.card_count,
        cardsightId: s.cardsight_id,
      })),
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-import-sets]', msg);
    return json({ error: msg }, 500);
  }
});
