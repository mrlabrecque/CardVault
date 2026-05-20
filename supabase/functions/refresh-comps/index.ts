/**
 * Legacy entrypoint: sold comps used to be scraped via Bright Data into `card_sold_comps`.
 * The app now persists guide sold comps via `cardhedge-grade-comps` only.
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
      error: 'refresh-comps_removed',
      message:
        'Marketplace scrape removed. Sold comps come from CardHedge (`cardhedge-grade-comps`); guide prices from `cardhedge-persist-variant` / `cardhedge-search-cards`.',
    }),
    { status: 410, headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
});
