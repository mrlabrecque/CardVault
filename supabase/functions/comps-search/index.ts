/**
 * Legacy text search for sold comps (Bright Data). Use catalog + CardHedge instead.
 */
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve((req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS, status: 200 });
  }
  return new Response(
    JSON.stringify({
      ok: false,
      deprecated: true,
      items: [],
      error: 'comps-search_removed',
      message: 'Free-text sold comp search was removed. Use CardHedge-backed flows from the catalog.',
    }),
    { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
});
