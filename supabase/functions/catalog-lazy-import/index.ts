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
      cardsightReleaseId, releaseName, releaseYear, releaseSegmentId, cardsightSetId,
    } = await req.json() as Record<string, string>;

    if (!cardsightReleaseId || !releaseName || !releaseYear || !cardsightSetId) {
      return json({ error: 'Missing required fields' }, 400);
    }

    const sport = releaseSegmentId
      ? (SEGMENT_TO_SPORT[String(releaseSegmentId).toLowerCase()] ?? null)
      : null;

    const slug = [releaseYear, releaseName, sport ?? '']
      .map(v => v.toLowerCase().trim().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''))
      .filter(Boolean)
      .join('-');

    // ── Upsert release ───────────────────────────────────────────────────────
    // Check if it already exists (preserve any admin edits to sport/type)
    const { data: existingRelease } = await supabase
      .from('releases')
      .select('id, name, sport')
      .eq('cardsight_id', cardsightReleaseId)
      .maybeSingle();

    let dbRelease = existingRelease;
    if (!dbRelease) {
      const { data, error } = await supabase
        .from('releases')
        .insert({ name: releaseName, year: parseInt(releaseYear, 10), sport, release_type: 'Hobby', set_slug: slug, cardsight_id: cardsightReleaseId })
        .select('id, name, sport')
        .single();
      if (error) throw new Error(error.message);
      dbRelease = data;
    }

    // ── Fetch set details from catalog ───────────────────────────────────────
    const setRes = await fetch(`${CARDSIGHT_BASE}/v1/catalog/sets/${cardsightSetId}`, {
      headers: { 'X-API-Key': apiKey },
    });
    if (!setRes.ok) throw new Error(`Catalog set fetch failed: ${setRes.status}`);
    const setDetail = await setRes.json() as {
      id: string; name: string; cardCount?: number;
      parallels?: Array<{ id: string; name: string; numberedTo?: number }>;
    };

    // ── Upsert set ───────────────────────────────────────────────────────────
    const { data: existingSet } = await supabase
      .from('sets')
      .select('id, name')
      .eq('cardsight_id', cardsightSetId)
      .maybeSingle();

    let dbSet = existingSet;
    if (!dbSet) {
      const { data, error } = await supabase
        .from('sets')
        .insert({ release_id: dbRelease.id, name: setDetail.name, card_count: setDetail.cardCount ?? null, cardsight_id: setDetail.id })
        .select('id, name')
        .single();
      if (error) throw new Error(error.message);
      dbSet = data;
    }

    // ── Upsert parallels ─────────────────────────────────────────────────────
    const parallels = setDetail.parallels ?? [];
    let dbParallels: unknown[] = [];
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
      const { data, error } = await supabase
        .from('set_parallels')
        .upsert(rows, { onConflict: 'set_id,name' })
        .select('id, set_id, name, serial_max, is_auto, color_hex, sort_order, created_at');
      if (error) throw new Error(error.message);
      dbParallels = data ?? [];
    }

    return json({
      releaseId:    dbRelease.id,
      releaseName:  dbRelease.name,
      releaseSport: dbRelease.sport,
      setId:        dbSet.id,
      setName:      dbSet.name,
      parallels:    dbParallels,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-lazy-import]', msg);
    return json({ error: msg }, 500);
  }
});
