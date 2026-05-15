import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
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

function countImportedSets(setsRaw: { set_cards?: { count?: number }[] }[]): number {
  let imported = 0;
  for (const s of setsRaw) {
    const defs = s.set_cards;
    if (defs != null && defs.length > 0 && (defs[0]?.count ?? 0) > 0) imported++;
  }
  return imported;
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
    const { segment } = await req.json() as { segment: string };
    if (!segment) return json({ error: 'segment is required' }, 400);

    const sport = segmentToSport(segment);
    const catalog = await fetchAllCardSightReleases(apiKey, segment);

    const { data: vaultRows, error: vaultError } = await supabase
      .from('releases')
      .select('id, name, year, sport, cardsight_id, sets(id, set_cards(count))')
      .eq('sport', sport);
    if (vaultError) throw new Error(vaultError.message);

    const vaultByCardsightId = new Map<string, {
      id: string;
      name: string;
      year: number | null;
      sport: string | null;
      cardsight_id: string;
      sets: { set_cards?: { count?: number }[] }[];
    }>();
    for (const row of vaultRows ?? []) {
      const csId = (row as { cardsight_id?: string }).cardsight_id;
      if (csId) vaultByCardsightId.set(csId, row as typeof vaultByCardsightId extends Map<string, infer V> ? V : never);
    }

    const releases = catalog.map((r) => {
      const year = parseInt(String(r.year), 10);
      const vault = vaultByCardsightId.get(r.id);
      const setsRaw = vault?.sets ?? [];
      return {
        cardsightId: r.id,
        name: r.name,
        year: Number.isFinite(year) ? year : null,
        inVault: vault != null,
        vaultReleaseId: vault?.id ?? null,
        setCount: setsRaw.length,
        importedSetCount: vault != null ? countImportedSets(setsRaw) : 0,
      };
    });

    const inVault = releases.filter((r) => r.inVault).length;

    return json({
      releases,
      total: releases.length,
      inVault,
      missing: releases.length - inVault,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-releases-list]', msg);
    return json({ error: msg }, 500);
  }
});
