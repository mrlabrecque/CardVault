import { createClient } from 'jsr:@supabase/supabase-js@2';

const CARDSIGHT_BASE = 'https://api.cardsight.ai';
const BATCH_SIZE = 20; // Process 20 cards per run
const DELAY_MS = 250; // Delay between CardSight calls

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function getCardSightImage(cardsightCardId: string): Promise<ArrayBuffer | null> {
  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) return null;

  try {
    const url = `${CARDSIGHT_BASE}/v1/images/cards/${cardsightCardId}`;
    const res = await fetch(url, { headers: { 'X-API-Key': apiKey } });
    if (!res.ok) return null;
    return res.arrayBuffer();
  } catch (e) {
    console.error('CardSight fetch error:', e);
    return null;
  }
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
      return json({ processed: 0 });
    }

    console.log(`[auto-fetch-card-images] processing ${cards.length} cards`);
    let processed = 0;
    let uploaded = 0;

    for (let i = 0; i < cards.length; i++) {
      if (i > 0) await new Promise(resolve => setTimeout(resolve, DELAY_MS));

      const card = cards[i];
      const imageBuffer = await getCardSightImage(card.cardsight_card_id);

      if (!imageBuffer) {
        console.log(`[auto-fetch-card-images] no image for ${card.cardsight_card_id}`);
        processed++;
        continue;
      }

      try {
        const storagePath = `cards/${card.cardsight_card_id}.jpg`;

        // Upload to storage
        const { error: uploadError } = await supabase.storage
          .from('card-images')
          .upload(storagePath, imageBuffer, { contentType: 'image/jpeg', upsert: true });

        if (uploadError) {
          console.log(`[auto-fetch-card-images] upload error for ${card.cardsight_card_id}:`, uploadError);
          processed++;
          continue;
        }

        // Get public URL
        const { data: { publicUrl } } = supabase.storage
          .from('card-images')
          .getPublicUrl(storagePath);

        // Update database
        const { error: updateError } = await supabase
          .from('master_card_definitions')
          .update({ image_url: publicUrl })
          .eq('id', card.id);

        if (updateError) {
          console.log(`[auto-fetch-card-images] update error for ${card.id}:`, updateError);
        } else {
          uploaded++;
        }

        processed++;
      } catch (e) {
        console.error('[auto-fetch-card-images] processing error:', e);
        processed++;
      }
    }

    console.log(`[auto-fetch-card-images] completed: ${processed} processed, ${uploaded} uploaded`);
    return json({ processed, uploaded });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[auto-fetch-card-images] exception:', msg);
    return json({ error: msg }, 500);
  }
});
