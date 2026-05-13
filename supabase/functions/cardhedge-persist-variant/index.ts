/**
 * Persists guide-price match data onto `master_card_definitions` + `current_prices`.
 * Auth: user JWT. Uses service role for Storage + DB writes.
 * Returns `persisted_master` snapshot for the client (no extra refetch).
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
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
    imageUrl: body.imageUrl,
    prices: body.prices,
    sales7d: body.sales7d,
    sales30d: body.sales30d,
    gain: body.gain,
  });

  const persisted_master = await fetchCatalogMasterSnapshot(admin, masterVariantId);

  return json({ ok: true, image_url: storedImageUrl, persisted_master });
});
