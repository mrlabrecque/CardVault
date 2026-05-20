/**
 * Legacy cron entrypoint: previously synced ESPN “top players” and wrote Bright Data / eBay
 * sold snapshots into `market_movers_snapshots`. The app now uses vault-based portfolio movers
 * (`portfolio_movers_from_vault` RPC). This handler stays deployable so old schedules return 200.
 */
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS, status: 200 });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const isServiceRole = token.length > 0 && token === serviceRoleKey;
  const hasJwt = token.length > 0;

  if (!isServiceRole && !hasJwt) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  return new Response(
    JSON.stringify({
      ok: true,
      deprecated: true,
      snapshotsWritten: 0,
      message:
        'Bright Data / eBay market-movers snapshot path removed. Use portfolio movers from vault data.',
    }),
    { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
  );
});
