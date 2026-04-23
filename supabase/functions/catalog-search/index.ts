import { createClient } from 'jsr:@supabase/supabase-js@2';

const CARDSIGHT_BASE = 'https://api.cardsight.ai';
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) return json({ error: 'API key not configured' }, 500);

  const csHeaders = { 'X-API-Key': apiKey };

  try {
    const body = await req.json() as Record<string, unknown>;

    // GET SETS for a specific release — body: { releaseId: string }
    if (body.releaseId) {
      const res = await fetch(`${CARDSIGHT_BASE}/v1/catalog/releases/${body.releaseId}`, { headers: csHeaders });
      if (!res.ok) throw new Error(`Catalog error: ${res.status}`);
      const data = await res.json() as { sets?: unknown[] };
      return json(data.sets ?? []);
    }

    // SEARCH releases — body: { query: string, year?: number }
    const url = new URL(`${CARDSIGHT_BASE}/v1/catalog/releases`);
    if (body.query) url.searchParams.set('manufacturer', String(body.query));
    if (body.year)  url.searchParams.set('year', String(body.year));
    const res = await fetch(url.toString(), { headers: csHeaders });
    if (!res.ok) throw new Error(`Catalog error: ${res.status}`);
    const data = await res.json() as { releases?: unknown[] };
    return json(data.releases ?? []);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    return json({ error: msg }, 500);
  }
});
