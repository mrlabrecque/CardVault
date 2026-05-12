/**
 * Proxies CardHedge GET /v1/cards/top-movers (market-wide gainers, cached upstream).
 * Auth: user JWT. OpenAPI: `count` 1–100, optional single `category` string (no array).
 * The Flutter client filters to catalog sports after one uncategorized fetch when needed.
 */
import { verifyUserJwt } from '../_shared/supabase_user_jwt.ts';

const UPSTREAM = 'https://api.cardhedger.com/v1/cards/top-movers';

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
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS, status: 200 });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Unauthorized' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const userId = await verifyUserJwt(authHeader, supabaseUrl);
  if (!userId) return json({ error: 'Unauthorized' }, 401);

  const apiKey =
    Deno.env.get('CARDHEDGE_API_KEY')?.trim() ||
    Deno.env.get('CARDHEDGER_API_KEY')?.trim();
  if (!apiKey) {
    return json({ error: 'CardHedge is not configured' }, 503);
  }

  let body: { category?: string | null; count?: number };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const rawCount = Number(body.count);
  const count = Math.min(100, Math.max(1, Number.isFinite(rawCount) ? Math.trunc(rawCount) : 20));
  const category = typeof body.category === 'string' ? body.category.trim() : '';
  const catParam = category.length > 0 ? category : undefined;

  const url = new URL(UPSTREAM);
  url.searchParams.set('count', String(count));
  if (catParam) url.searchParams.set('category', catParam);

  const upstream = await fetch(url.toString(), {
    method: 'GET',
    headers: { 'X-API-Key': apiKey },
  });

  const text = await upstream.text();
  if (!upstream.ok) {
    console.error('[cardhedge-top-movers] upstream', upstream.status, text.slice(0, 2000));
    return json(
      {
        error: 'CardHedge top movers request failed',
        status: upstream.status,
        details: text.slice(0, 500),
      },
      502,
    );
  }

  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch {
    return json({ error: 'Invalid JSON from CardHedge' }, 502);
  }

  return json(payload, 200);
});
