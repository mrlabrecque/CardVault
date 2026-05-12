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
    const masterCardId = body?.masterCardId as string | undefined;
    console.log('[fetch-card-image] masterCardId:', masterCardId);

    if (!masterCardId) {
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') || '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '',
    );

    let setCardId = masterCardId;
    let cardsightCardId: string | null = null;
    let existingImageUrl: string | null = null;

    const { data: variantRow, error: vErr } = await supabase
      .from('master_card_definitions')
      .select('set_card_id, set_cards ( cardsight_card_id, image_url )')
      .eq('id', masterCardId)
      .maybeSingle();

    if (!vErr && variantRow) {
      const sc = variantRow.set_cards as { cardsight_card_id: string | null; image_url: string | null } | null;
      setCardId = variantRow.set_card_id as string;
      cardsightCardId = sc?.cardsight_card_id ?? null;
      existingImageUrl = sc?.image_url ?? null;
    } else {
      const { data: sc, error: scErr } = await supabase
        .from('set_cards')
        .select('cardsight_card_id, image_url')
        .eq('id', masterCardId)
        .maybeSingle();
      if (scErr || !sc) {
        console.log('[fetch-card-image] not found as variant or set_card');
        return new Response(JSON.stringify({ image_url: null }), { status: 200 });
      }
      cardsightCardId = sc.cardsight_card_id;
      existingImageUrl = sc.image_url;
    }

    console.log('[fetch-card-image] set_card_id:', setCardId, 'image_url:', existingImageUrl);

    if (existingImageUrl) {
      return new Response(JSON.stringify({ image_url: existingImageUrl }), { status: 200 });
    }

    if (!cardsightCardId) {
      console.log('[fetch-card-image] no cardsight_card_id, returning null');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    if (!Deno.env.get('CARDSIGHT_API_KEY')) {
      console.log('[fetch-card-image] no CARDSIGHT_API_KEY');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    console.log('[fetch-card-image] fetching from CardSight, id:', cardsightCardId);

    const publicUrl = await fetchUploadAndSetMasterImage(supabase, {
      masterCardId: setCardId,
      cardsightCardId,
    });

    console.log(publicUrl ? '[fetch-card-image] success' : '[fetch-card-image] failed after fetch/upload');
    return new Response(JSON.stringify({ image_url: publicUrl }), { status: 200 });
  } catch (e) {
    console.error('[fetch-card-image] exception:', e);
    return new Response(JSON.stringify({ image_url: null }), { status: 200 });
  }
});
