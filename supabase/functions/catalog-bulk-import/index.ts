import { createClient } from 'jsr:@supabase/supabase-js@2';

const CARDSIGHT_BASE = 'https://api.cardsight.ai';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Max-Age': '86400',
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
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS, status: 200 });

  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) return json({ error: 'API key not configured' }, 500);

  // Admin-only: verify JWT and check is_app_admin
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Missing authorization' }, 401);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Validate caller is an admin
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
    const { year, segment, skip = 0 } = await req.json() as {
      year: number;
      segment: string;
      skip?: number;
    };

    if (!year || !segment) {
      return json({ error: 'year and segment are required' }, 400);
    }

    const sport = SEGMENT_TO_SPORT[String(segment).toLowerCase()] ?? 'Unknown';

    // Fetch up to 100 releases from CardSight
    const url = new URL(`${CARDSIGHT_BASE}/v1/catalog/releases`);
    url.searchParams.set('year', String(year));
    url.searchParams.set('segment', segment);
    url.searchParams.set('take', '100');
    url.searchParams.set('skip', String(skip));

    const csRes = await fetch(url.toString(), {
      headers: { 'X-API-Key': apiKey },
    });
    if (!csRes.ok) throw new Error(`CardSight API error: ${csRes.status}`);

    const csData = await csRes.json() as { releases?: Array<{ id: string; name: string; year: string }> };
    const releases = csData.releases ?? (Array.isArray(csData) ? csData as Array<{ id: string; name: string; year: string }> : []);

    if (releases.length === 0) {
      return json({ imported: 0, total: 0 });
    }

    // Build upsert rows — shell only, no sets/parallels/cards
    const rows = releases.map(r => {
      const releaseYear = parseInt(String(r.year), 10);
      const slug = [r.year, r.name, sport]
        .map(v => String(v).toLowerCase().trim().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''))
        .filter(Boolean)
        .join('-');
      return {
        name:         r.name,
        year:         releaseYear,
        sport,
        release_type: 'Hobby',
        set_slug:     slug,
        cardsight_id: r.id,
      };
    });

    const { data: upserted, error: upsertError } = await supabase
      .from('releases')
      .upsert(rows, { onConflict: 'cardsight_id', ignoreDuplicates: true })
      .select('cardsight_id');

    if (upsertError) throw new Error(upsertError.message);

    const newIds = new Set(upserted?.map((r: { cardsight_id: string }) => r.cardsight_id) ?? []);
    const releaseList = rows.map(r => ({
      name:   r.name,
      year:   r.year,
      is_new: newIds.has(r.cardsight_id),
    }));

    return json({
      imported: upserted?.length ?? 0,
      total:    rows.length,
      releases: releaseList,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-bulk-import]', msg);
    return json({ error: msg }, 500);
  }
});
