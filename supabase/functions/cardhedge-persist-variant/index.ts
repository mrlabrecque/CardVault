/**
 * Persists guide-price match data onto `master_card_definitions` + `current_prices`.
 * Auth: user JWT. Uses service role for Storage + DB writes.
 * Returns `persisted_master` snapshot for the client (no extra refetch).
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { hydratePersistFieldsFromCardHedgeCardId } from '../_shared/cardhedge_hydrate_variant.ts';
import { fetchCatalogMasterSnapshot, persistGuidePricesOntoMaster } from '../_shared/cardhedge_persist_master.ts';
import { verifyUserJwt } from '../_shared/supabase_user_jwt.ts';

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
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const userId = await verifyUserJwt(authHeader, supabaseUrl);
  if (!userId) return json({ error: 'Unauthorized' }, 401);

  let body: {
    masterVariantId?: string;
    guidePriceCardId?: string;
    /** @deprecated Prefer guidePriceCardId; accepted for older app builds. */
    cardhedgeId?: string;
    imageUrl?: string | null;
    prices?: unknown[];
    sales7d?: unknown;
    sales30d?: unknown;
    gain?: unknown;
    /** When true with [guidePriceCardId] and no usable [prices], fetch CardHedge `card-details` (+ prices backfill). */
    hydrateFromCardHedge?: boolean;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const masterVariantId = body.masterVariantId?.trim();
  if (!masterVariantId) return json({ error: 'masterVariantId required' }, 400);

  const guidePriceCardId =
    (typeof body.guidePriceCardId === 'string' ? body.guidePriceCardId.trim() : '') ||
    (typeof body.cardhedgeId === 'string' ? body.cardhedgeId.trim() : '') ||
    undefined;

  const apiKey =
    Deno.env.get('CARDHEDGE_API_KEY')?.trim() ||
    Deno.env.get('CARDHEDGER_API_KEY')?.trim() ||
    '';

  let pricesIn = body.prices;
  let sales7In = body.sales7d;
  let sales30In = body.sales30d;
  let gainIn = body.gain;
  let imageIn = body.imageUrl;

  const pricesArr = Array.isArray(pricesIn) ? pricesIn : [];
  const hydrate = Boolean(body.hydrateFromCardHedge);
  if (
    hydrate &&
    guidePriceCardId &&
    apiKey &&
    pricesArr.length === 0
  ) {
    const h = await hydratePersistFieldsFromCardHedgeCardId(apiKey, guidePriceCardId);
    if (h.prices && h.prices.length > 0) pricesIn = h.prices;
    if (sales7In === undefined || sales7In === null) sales7In = h.sales7d ?? undefined;
    if (sales30In === undefined || sales30In === null) sales30In = h.sales30d ?? undefined;
    if (gainIn === undefined || gainIn === null) gainIn = h.gain ?? undefined;
    const imgTrim = typeof imageIn === 'string' ? imageIn.trim() : '';
    if ((!imgTrim || imgTrim.length === 0) && h.imageUrl) imageIn = h.imageUrl;
  }

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: row, error: qErr } = await admin
    .from('master_card_definitions')
    .select('id')
    .eq('id', masterVariantId)
    .maybeSingle();

  if (qErr || !row) return json({ error: 'Variant not found' }, 404);

  const { storedImageUrl } = await persistGuidePricesOntoMaster(admin, {
    masterVariantId,
    guidePriceCardId,
    imageUrl: imageIn,
    prices: pricesIn,
    sales7d: sales7In,
    sales30d: sales30In,
    gain: gainIn,
  });

  const persisted_master = await fetchCatalogMasterSnapshot(admin, masterVariantId);

  return json({ ok: true, image_url: storedImageUrl, persisted_master });
});
