import { createClient } from 'jsr:@supabase/supabase-js@2';
import { fetchUploadAndSetMasterImage } from '../_shared/card_image_cardsight.ts';

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
      .select('cardsight_card_id, image_url')
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

    if (!Deno.env.get('CARDSIGHT_API_KEY')) {
      console.log('[fetch-card-image] no CARDSIGHT_API_KEY');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    console.log('[fetch-card-image] fetching from CardSight, id:', card.cardsight_card_id);

    const publicUrl = await fetchUploadAndSetMasterImage(supabase, {
      masterCardId,
      cardsightCardId: card.cardsight_card_id,
    });

    console.log(publicUrl ? '[fetch-card-image] success' : '[fetch-card-image] failed after fetch/upload');
    return new Response(JSON.stringify({ image_url: publicUrl }), { status: 200 });
  } catch (e) {
    console.error('[fetch-card-image] exception:', e);
    return new Response(JSON.stringify({ image_url: null }), { status: 200 });
  }
});
