/**
 * CardSight card image → Supabase Storage (`card-images`) → `master_card_definitions.image_url`.
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

/**
 * Uploads JPEG bytes, updates `master_card_definitions` for `masterCardId`, returns public URL or null.
 */
export async function uploadCardImageAndUpdateMaster(
  supabase: SupabaseClient,
  params: { masterCardId: string; cardsightCardId: string; imageBuffer: ArrayBuffer },
): Promise<string | null> {
  const { masterCardId, cardsightCardId, imageBuffer } = params;
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
    .from('master_card_definitions')
    .update({ image_url: publicUrl })
    .eq('id', masterCardId);

  if (updateError) {
    console.log('[card-image] update error:', updateError);
    return null;
  }

  return publicUrl;
}

/**
 * Fetches from CardSight, uploads, updates row. Returns public URL or null on any failure.
 */
export async function fetchUploadAndSetMasterImage(
  supabase: SupabaseClient,
  params: { masterCardId: string; cardsightCardId: string },
): Promise<string | null> {
  const imageBuffer = await fetchCardsightCardImageBytes(params.cardsightCardId);
  if (!imageBuffer) return null;
  return uploadCardImageAndUpdateMaster(supabase, {
    ...params,
    imageBuffer,
  });
}
