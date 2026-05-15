import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  CARDSIGHT_RELEASES_PAGE_SIZE,
  fetchAllCardSightReleases,
  segmentToSport,
} from '../_shared/cardsight_catalog_releases.ts';

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
    const { year, segment, releases: selected } = await req.json() as {
      year?: number;
      segment: string;
      releases?: { cardsightId: string; name: string; year?: number | null }[];
    };

    if (!segment) {
      return json({ error: 'segment is required' }, 400);
    }

    const sport = segmentToSport(segment);

    let catalogReleases: { id: string; name: string; year: string }[];
    if (selected != null && selected.length > 0) {
      catalogReleases = selected.map((r) => ({
        id: r.cardsightId,
        name: r.name,
        year: r.year != null ? String(r.year) : '',
      }));
    } else {
      catalogReleases = await fetchAllCardSightReleases(apiKey, segment, year);
    }

    if (catalogReleases.length === 0) {
      return json({ imported: 0, total: 0, pages_fetched: 0 });
    }

    const resolveYear = (yearStr: string, name: string): number => {
      const parsed = parseInt(String(yearStr), 10);
      if (Number.isFinite(parsed) && parsed > 1900) return parsed;
      const fromName = name.match(/\b(19|20)\d{2}\b/);
      if (fromName) return parseInt(fromName[0], 10);
      return new Date().getFullYear();
    };

    const releaseSlug = (year: number, name: string, cardsightId: string): string => {
      const base = [String(year), name, sport]
        .map((v) => String(v).toLowerCase().trim().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''))
        .filter(Boolean)
        .join('-');
      const tail = cardsightId.replace(/[^a-zA-Z0-9]/g, '').toLowerCase().slice(0, 8);
      return tail ? `${base}-${tail}` : base;
    };

    const rows = catalogReleases.map(r => {
      const releaseYear = resolveYear(r.year, r.name);
      return {
        name:         r.name,
        year:         releaseYear,
        sport,
        release_type: 'Hobby',
        set_slug:     releaseSlug(releaseYear, r.name, r.id),
        cardsight_id: r.id,
      };
    });

    const allIds = rows.map((r) => r.cardsight_id);
    const { data: existingRows, error: existingError } = await supabase
      .from('releases')
      .select('cardsight_id')
      .in('cardsight_id', allIds);
    if (existingError) throw new Error(existingError.message);

    const existingIds = new Set(
      (existingRows ?? []).map((r: { cardsight_id: string }) => r.cardsight_id),
    );

    const UPSERT_CHUNK = 200;
    const newIds = new Set<string>();
    for (let i = 0; i < rows.length; i += UPSERT_CHUNK) {
      const chunk = rows.slice(i, i + UPSERT_CHUNK);
      const { data: upserted, error: upsertError } = await supabase
        .from('releases')
        .upsert(chunk, { onConflict: 'cardsight_id' })
        .select('cardsight_id');

      if (upsertError) throw new Error(upsertError.message);
      for (const r of upserted ?? []) {
        const id = (r as { cardsight_id: string }).cardsight_id;
        if (!existingIds.has(id)) newIds.add(id);
      }
    }

    const releaseList = rows.map(r => ({
      name:   r.name,
      year:   r.year,
      is_new: newIds.has(r.cardsight_id),
    }));

    const pagesFetched = selected?.length
      ? 0
      : Math.ceil(catalogReleases.length / CARDSIGHT_RELEASES_PAGE_SIZE);

    return json({
      imported: newIds.size,
      total:    rows.length,
      pages_fetched: pagesFetched,
      releases: releaseList,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-bulk-import]', msg);
    return json({ error: msg }, 500);
  }
});
