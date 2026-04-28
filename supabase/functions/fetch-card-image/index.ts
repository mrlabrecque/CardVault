import { createClient } from 'jsr:@supabase/supabase-js@2';

const CARDSIGHT_BASE = 'https://api.cardsight.ai';

Deno.serve(async (req) => {
  console.log('[fetch-card-image] received request');

  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    });
  }

  try {
    const body = await req.json();
    const masterCardId = body?.masterCardId;
    console.log('[fetch-card-image] masterCardId:', masterCardId);

    if (!masterCardId) {
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') || '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '',
    );

    console.log('[fetch-card-image] querying card');
    const { data: card, error: queryError } = await supabase
      .from('master_card_definitions')
      .select('cardsight_card_id, image_url, player, card_number, set_id')
      .eq('id', masterCardId)
      .single();

    if (queryError) {
      console.log('[fetch-card-image] query error:', queryError);
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    if (!card) {
      console.log('[fetch-card-image] card not found');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    console.log('[fetch-card-image] card found, image_url:', card.image_url);

    if (card.image_url) {
      return new Response(JSON.stringify({ image_url: card.image_url }), { status: 200 });
    }

    if (!card.cardsight_card_id) {
      console.log('[fetch-card-image] no cardsight_card_id, returning null');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    console.log('[fetch-card-image] fetching from CardSight, id:', card.cardsight_card_id);
    const apiKey = Deno.env.get('CARDSIGHT_API_KEY');

    if (!apiKey) {
      console.log('[fetch-card-image] no CARDSIGHT_API_KEY');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    const imgUrl = `${CARDSIGHT_BASE}/v1/images/cards/${card.cardsight_card_id}`;
    console.log('[fetch-card-image] calling:', imgUrl);

    const imgRes = await fetch(imgUrl, { headers: { 'X-API-Key': apiKey } });
    console.log('[fetch-card-image] CardSight response:', imgRes.status);

    if (!imgRes.ok) {
      console.log('[fetch-card-image] CardSight error');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    const imageBuffer = await imgRes.arrayBuffer();
    console.log('[fetch-card-image] got image, size:', imageBuffer.byteLength);

    const storagePath = `cards/${card.cardsight_card_id}.jpg`;
    console.log('[fetch-card-image] uploading to:', storagePath);

    const { error: uploadError } = await supabase.storage
      .from('card-images')
      .upload(storagePath, imageBuffer, { contentType: 'image/jpeg', upsert: true });

    if (uploadError) {
      console.log('[fetch-card-image] upload error:', uploadError);
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    const { data: { publicUrl } } = supabase.storage
      .from('card-images')
      .getPublicUrl(storagePath);

    console.log('[fetch-card-image] got public url:', publicUrl);

    const { error: updateError } = await supabase
      .from('master_card_definitions')
      .update({ image_url: publicUrl })
      .eq('id', masterCardId);

    if (updateError) {
      console.log('[fetch-card-image] update error:', updateError);
    }

    console.log('[fetch-card-image] success');
    return new Response(JSON.stringify({ image_url: publicUrl }), { status: 200 });
  } catch (e) {
    console.error('[fetch-card-image] exception:', e);
    return new Response(JSON.stringify({ image_url: null }), { status: 200 });
  }
});
