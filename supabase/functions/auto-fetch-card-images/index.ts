import { createClient } from 'jsr:@supabase/supabase-js@2';
import { fetchUploadAndSetMasterImage } from '../_shared/card_image_cardsight.ts';

const BATCH_SIZE = 20; // Process 20 cards per run
const DELAY_MS = 250; // Delay between CardSight calls

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') || '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '',
  );

  try {
    console.log('[auto-fetch-card-images] starting');

    // Find cards with cardsight_card_id but no image_url
    const { data: cards, error: queryError } = await supabase
      .from('master_card_definitions')
      .select('id, cardsight_card_id')
      .not('cardsight_card_id', 'is', null)
      .is('image_url', null)
      .limit(BATCH_SIZE);

    if (queryError) {
      console.error('[auto-fetch-card-images] query error:', queryError);
      return json({ error: queryError.message }, 500);
    }

    if (!cards || cards.length === 0) {
      console.log('[auto-fetch-card-images] no cards to fetch');
      return json({ processed: 0, uploaded: 0 });
    }

    console.log(`[auto-fetch-card-images] processing ${cards.length} cards`);
    let processed = 0;
    let uploaded = 0;

    for (let i = 0; i < cards.length; i++) {
      if (i > 0) await new Promise(resolve => setTimeout(resolve, DELAY_MS));

      const card = cards[i];
      const publicUrl = await fetchUploadAndSetMasterImage(supabase, {
        masterCardId: card.id,
        cardsightCardId: card.cardsight_card_id,
      });

      processed++;
      if (publicUrl) uploaded++;
      else console.log(`[auto-fetch-card-images] no image for ${card.cardsight_card_id}`);
    }

    console.log(`[auto-fetch-card-images] completed: ${processed} processed, ${uploaded} uploaded`);
    return json({ processed, uploaded });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[auto-fetch-card-images] exception:', msg);
    return json({ error: msg }, 500);
  }
});
