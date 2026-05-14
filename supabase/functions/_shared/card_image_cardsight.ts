/**
 * CardSight card image → Supabase Storage (`card-images`) → `set_cards.image_url`
 * and, for the **base** checklist parallel only, `master_card_definitions.image_url`.
 * Non-base parallel images should use a separate pipeline (not implemented here).
 */

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

const CARDSIGHT_BASE = 'https://api.cardsight.ai';

export async function fetchCardsightCardImageBytes(cardsightCardId: string): Promise<ArrayBuffer | null> {
  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) return null;
  try {
    const url = `${CARDSIGHT_BASE}/v1/images/cards/${cardsightCardId}`;
    const res = await fetch(url, { headers: { 'X-API-Key': apiKey } });
    if (!res.ok) return null;
    return res.arrayBuffer();
  } catch (e) {
    console.error('[card-image] CardSight fetch error:', e);
    return null;
  }
}

/** Mirrors DB `_default_parallel_for_set`: Base name first, then sort_order, then name. */
export async function getDefaultParallelIdForSet(
  supabase: SupabaseClient,
  setId: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from('set_parallels')
    .select('id, name, sort_order')
    .eq('set_id', setId);
  if (error || !data?.length) return null;
  const sorted = [...data].sort((a, b) => {
    const ab = a.name.trim().toLowerCase() === 'base' ? 0 : 1;
    const bb = b.name.trim().toLowerCase() === 'base' ? 0 : 1;
    if (ab !== bb) return ab - bb;
    const so = (x: (typeof data)[0]) => x.sort_order ?? 999999;
    return so(a) - so(b);
  });
  return sorted[0]?.id ?? null;
}

/**
 * When the CardSight checklist image is stored on `set_cards`, also write
 * `master_card_definitions.image_url` for the **base** variant row
 * (`set_card_id` + default parallel for `set_id`).
 *
 * If [catalogVariantId] is set, only update the base master row when that variant
 * is the base parallel (skip for Silver / etc. — different route later).
 */
export async function syncBaseVariantMasterImageUrl(
  supabase: SupabaseClient,
  params: {
    setCardId: string;
    setId: string;
    publicUrl: string;
    catalogVariantId?: string | null;
  },
): Promise<void> {
  const { setCardId, setId, publicUrl, catalogVariantId } = params;
  const defaultPid = await getDefaultParallelIdForSet(supabase, setId);
  if (!defaultPid) return;

  if (catalogVariantId) {
    const { data: row } = await supabase
      .from('master_card_definitions')
      .select('parallel_id')
      .eq('id', catalogVariantId)
      .maybeSingle();
    if (!row || row.parallel_id !== defaultPid) return;
  }

  const { error } = await supabase
    .from('master_card_definitions')
    .update({ image_url: publicUrl })
    .eq('set_card_id', setCardId)
    .eq('parallel_id', defaultPid);

  if (error) {
    console.error('[card-image] master_card_definitions (base) update:', error);
  }
}

/**
 * Uploads JPEG bytes, updates `set_cards`, then mirrors to base-variant
 * `master_card_definitions` when applicable.
 */
export async function uploadCardImageAndUpdateMaster(
  supabase: SupabaseClient,
  params: {
    setCardId: string;
    setId: string;
    cardsightCardId: string;
    imageBuffer: ArrayBuffer;
    catalogVariantId?: string | null;
  },
): Promise<string | null> {
  const { setCardId, setId, cardsightCardId, imageBuffer, catalogVariantId } = params;
  const storagePath = `cards/${cardsightCardId}.jpg`;

  const { error: uploadError } = await supabase.storage
    .from('card-images')
    .upload(storagePath, imageBuffer, { contentType: 'image/jpeg', upsert: true });

  if (uploadError) {
    console.log('[card-image] upload error:', uploadError);
    return null;
  }

  const { data: { publicUrl } } = supabase.storage.from('card-images').getPublicUrl(storagePath);

  const { error: updateError } = await supabase
    .from('set_cards')
    .update({ image_url: publicUrl })
    .eq('id', setCardId);

  if (updateError) {
    console.log('[card-image] set_cards update error:', updateError);
    return null;
  }

  await syncBaseVariantMasterImageUrl(supabase, {
    setCardId,
    setId,
    publicUrl,
    catalogVariantId: catalogVariantId ?? null,
  });

  return publicUrl;
}

/**
 * Fetches from CardSight, uploads, updates `set_cards` + base variant `master_card_definitions`
 * when the resolved row is (or caller only had) the base parallel path.
 */
export async function fetchUploadAndSetMasterImage(
  supabase: SupabaseClient,
  params: {
    setCardId: string;
    setId: string;
    cardsightCardId: string;
    catalogVariantId?: string | null;
  },
): Promise<string | null> {
  const imageBuffer = await fetchCardsightCardImageBytes(params.cardsightCardId);
  if (!imageBuffer) return null;
  return uploadCardImageAndUpdateMaster(supabase, {
    ...params,
    imageBuffer,
  });
}
