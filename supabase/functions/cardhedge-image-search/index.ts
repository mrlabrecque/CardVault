/**
 * Proxies CardHedge POST /v1/cards/image-search (JWT auth; API key server-side).
 */
import { verifyUserJwt } from '../_shared/supabase_user_jwt.ts';

const UPSTREAM = 'https://api.cardhedger.com/v1/cards/image-search';

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

type CardData = {
  card_id?: string;
  player?: string;
  set?: string;
  number?: string;
  variant?: string;
  category?: string;
  description?: string;
  image?: string;
};

function normalizeHit(raw: Record<string, unknown>): Record<string, unknown> | null {
  const cd = raw.card_data;
  if (!cd || typeof cd !== 'object') return null;
  const c = cd as CardData;
  const cardId = typeof c.card_id === 'string' ? c.card_id.trim() : '';
  if (!cardId) return null;
  return {
    similarity: typeof raw.similarity === 'string' ? raw.similarity : String(raw.similarity ?? ''),
    distance: typeof raw.distance === 'number' && Number.isFinite(raw.distance) ? raw.distance : null,
    card_id: cardId,
    player: typeof c.player === 'string' ? c.player : null,
    set: typeof c.set === 'string' ? c.set : null,
    number: c.number === null || c.number === undefined ? null : String(c.number),
    variant: typeof c.variant === 'string' ? c.variant : null,
    category: typeof c.category === 'string' ? c.category : null,
    description: typeof c.description === 'string' ? c.description : null,
    image: typeof c.image === 'string' ? c.image : null,
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS, status: 200 });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Unauthorized' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const userId = await verifyUserJwt(authHeader, supabaseUrl);
  if (!userId) return json({ error: 'Unauthorized' }, 401);

  const apiKey =
    Deno.env.get('CARDHEDGE_API_KEY')?.trim() ||
    Deno.env.get('CARDHEDGER_API_KEY')?.trim();
  if (!apiKey) {
    return json(
      {
        error: 'CardHedge is not configured',
        hint: 'Add CARDHEDGE_API_KEY to Edge Function secrets and deploy cardhedge-image-search.',
      },
      503,
    );
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json() as Record<string, unknown>;
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const b64Raw = body.image_base64 ?? body.imageBase64;
  const urlRaw = body.image_url ?? body.imageUrl;
  const imageBase64 = typeof b64Raw === 'string' ? b64Raw.trim() : '';
  const imageUrl = typeof urlRaw === 'string' ? urlRaw.trim() : '';

  if (!imageBase64 && !imageUrl) {
    return json({ error: 'image_base64 or image_url is required' }, 400);
  }

  const kRaw = body.k ?? body.K;
  let k = typeof kRaw === 'number' && Number.isFinite(kRaw) ? Math.trunc(kRaw) : 10;
  if (k < 1) k = 1;
  if (k > 50) k = 50;

  const upstreamBody: Record<string, unknown> = { k };
  if (imageBase64) {
    upstreamBody.image_base64 = imageBase64.startsWith('data:')
      ? imageBase64
      : `data:image/jpeg;base64,${imageBase64}`;
  } else {
    upstreamBody.image_url = imageUrl;
  }

  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), 55_000);
  let res: Response;
  try {
    res = await fetch(UPSTREAM, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      },
      body: JSON.stringify(upstreamBody),
      signal: controller.signal,
    });
  } catch (e) {
    const msg = e instanceof Error && e.name === 'AbortError' ? 'CardHedge image-search timed out' : String(e);
    return json({ error: msg }, 504);
  } finally {
    clearTimeout(t);
  }

  const text = await res.text();
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(text) as Record<string, unknown>;
  } catch {
    return json({ error: 'CardHedge returned non-JSON', status: res.status }, 502);
  }

  if (!res.ok) {
    return json(
      {
        error: typeof data.detail === 'string' ? data.detail : `CardHedge HTTP ${res.status}`,
        details: data,
      },
      res.status >= 400 && res.status < 600 ? res.status : 502,
    );
  }

  const resultsRaw = data.results;
  const hits: Record<string, unknown>[] = [];
  if (Array.isArray(resultsRaw)) {
    for (const item of resultsRaw) {
      if (!item || typeof item !== 'object') continue;
      const hit = normalizeHit(item as Record<string, unknown>);
      if (hit) hits.push(hit);
    }
  }

  return json({
    success: data.success === true,
    has_cardhedge_matches: data.has_cardhedge_matches === true,
    query_id: typeof data.query_id === 'string' ? data.query_id : null,
    total_results: typeof data.total_results === 'number' ? data.total_results : hits.length,
    hits,
    message: typeof data.message === 'string' ? data.message : null,
  });
});
