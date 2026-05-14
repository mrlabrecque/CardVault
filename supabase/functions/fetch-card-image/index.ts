import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  fetchCardsightCardImageBytes,
  fetchUploadAndSetMasterImage,
  syncBaseVariantMasterImageUrl,
} from '../_shared/card_image_cardsight.ts';

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
    const masterCardId = (body?.masterCardId as string | undefined)?.trim();
    console.log('[fetch-card-image] masterCardId:', masterCardId);

    if (!masterCardId) {
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') || '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '',
    );

    type SetCardNested = {
      cardsight_card_id: string | null;
      image_url: string | null;
      set_id: string | null;
    } | null;

    type SetCardRow = {
      id: string;
      cardsight_card_id: string | null;
      image_url: string | null;
      set_id: string | null;
    };

    let setCardId: string;
    let setId: string | null = null;
    let cardsightCardId: string | null = null;
    let existingSetCardImageUrl: string | null = null;
    let catalogVariantId: string | null = null;

    const { data: variantRow, error: vErr } = await supabase
      .from('master_card_definitions')
      .select('id, set_card_id, image_url, set_cards ( cardsight_card_id, image_url, set_id )')
      .eq('id', masterCardId)
      .maybeSingle();

    if (!vErr && variantRow) {
      catalogVariantId = variantRow.id as string;
      const variantImg = typeof variantRow.image_url === 'string' ? variantRow.image_url.trim() : '';
      if (variantImg) {
        return new Response(JSON.stringify({ image_url: variantImg }), { status: 200 });
      }

      const sc = variantRow.set_cards as SetCardNested;
      setCardId = variantRow.set_card_id as string;
      cardsightCardId = sc?.cardsight_card_id ?? null;
      existingSetCardImageUrl = sc?.image_url ?? null;
      setId = sc?.set_id ?? null;
    } else {
      const { data: scByPk, error: scErr } = await supabase
        .from('set_cards')
        .select('id, cardsight_card_id, image_url, set_id')
        .eq('id', masterCardId)
        .maybeSingle();

      if (!scErr && scByPk) {
        const sc = scByPk as SetCardRow;
        setCardId = sc.id;
        setId = sc.set_id;
        cardsightCardId = sc.cardsight_card_id;
        existingSetCardImageUrl = sc.image_url;
        catalogVariantId = null;
      } else {
        // CardSight identify often returns `card.id` = CardSight catalog card id, stored on set_cards.cardsight_card_id
        const { data: scByCs, error: csErr } = await supabase
          .from('set_cards')
          .select('id, cardsight_card_id, image_url, set_id')
          .eq('cardsight_card_id', masterCardId)
          .maybeSingle();

        if (csErr || !scByCs) {
          console.log(
            '[fetch-card-image] no DB row for variant id, set_cards.id, or cardsight_card_id — trying CardSight-only (scan / pre-import)',
          );
          if (Deno.env.get('CARDSIGHT_API_KEY')) {
            const buf = await fetchCardsightCardImageBytes(masterCardId);
            if (buf) {
              const storagePath = `cards/${masterCardId}.jpg`;
              const { error: upErr } = await supabase.storage
                .from('card-images')
                .upload(storagePath, buf, { contentType: 'image/jpeg', upsert: true });
              if (!upErr) {
                const { data: { publicUrl } } = supabase.storage.from('card-images').getPublicUrl(storagePath);
                console.log('[fetch-card-image] CardSight-only success (no catalog row yet)');
                return new Response(JSON.stringify({ image_url: publicUrl }), { status: 200 });
              }
              console.log('[fetch-card-image] CardSight-only upload error:', upErr);
            }
          }
          return new Response(JSON.stringify({ image_url: null }), { status: 200 });
        }
        const sc = scByCs as SetCardRow;
        setCardId = sc.id;
        setId = sc.set_id;
        cardsightCardId = sc.cardsight_card_id;
        existingSetCardImageUrl = sc.image_url;
        catalogVariantId = null;
      }
    }

    console.log('[fetch-card-image] set_card_id:', setCardId, 'set_id:', setId, 'checklist image_url:', existingSetCardImageUrl);

    if (existingSetCardImageUrl?.trim()) {
      const u = existingSetCardImageUrl.trim();
      await syncBaseVariantMasterImageUrl(supabase, {
        setCardId,
        setId,
        publicUrl: u,
        catalogVariantId,
      });
      return new Response(JSON.stringify({ image_url: u }), { status: 200 });
    }

    if (!setId) {
      console.log('[fetch-card-image] missing set_id on set_cards row');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    if (!cardsightCardId) {
      console.log('[fetch-card-image] no cardsight_card_id, returning null');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    if (!Deno.env.get('CARDSIGHT_API_KEY')) {
      console.log('[fetch-card-image] no CARDSIGHT_API_KEY');
      return new Response(JSON.stringify({ image_url: null }), { status: 200 });
    }

    console.log('[fetch-card-image] fetching CardSight image, cardsight_card_id:', cardsightCardId);

    const publicUrl = await fetchUploadAndSetMasterImage(supabase, {
      setCardId,
      setId,
      cardsightCardId,
      catalogVariantId,
    });

    console.log(publicUrl ? '[fetch-card-image] success' : '[fetch-card-image] failed after fetch/upload');
    return new Response(JSON.stringify({ image_url: publicUrl }), { status: 200 });
  } catch (e) {
    console.error('[fetch-card-image] exception:', e);
    return new Response(JSON.stringify({ image_url: null }), { status: 200 });
  }
});
