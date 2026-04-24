import { createClient } from 'jsr:@supabase/supabase-js@2';

const CARDSIGHT_BASE = 'https://api.cardsight.ai';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Max-Age': '86400',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS, status: 200 });

  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) return json({ error: 'API key not configured' }, 500);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  try {
    const { cardsightReleaseId, cardsightSetId, setId } = await req.json() as {
      cardsightReleaseId: string;
      cardsightSetId: string;
      setId?: string;
    };

    if (!cardsightReleaseId || !cardsightSetId) {
      return json({ error: 'cardsightReleaseId and cardsightSetId are required' }, 400);
    }

    // ── Fetch cards from CardSight ────────────────────────────────────────────
    // Use release endpoint with setId filter; paginate if needed
    let allCards: Array<{
      id: string;
      number: string;
      name: string;
      attributes?: string[];
    }> = [];
    let page = 0;
    let hasMore = true;

    while (hasMore) {
      const url = new URL(`${CARDSIGHT_BASE}/v1/catalog/releases/${cardsightReleaseId}/cards`);
      url.searchParams.set('setId', cardsightSetId);
      url.searchParams.set('take', '100');
      url.searchParams.set('skip', String(page * 100));

      const csRes = await fetch(url.toString(), {
        headers: { 'X-Api-Key': apiKey },
      });
      if (!csRes.ok) throw new Error(`CardSight cards fetch failed: ${csRes.status}`);

      const csData = await csRes.json() as {
        cards?: Array<{
          id: string;
          number: string;
          name: string;
          attributes?: string[];
        }>;
        total_count?: number;
      };
      const cards = csData.cards ?? [];
      if (cards.length === 0) {
        hasMore = false;
      } else {
        allCards = [...allCards, ...cards];
        hasMore = cards.length === 100;
        page++;
      }
      // Small delay to avoid rate-limiting
      await new Promise(r => setTimeout(r, 250));
    }

    if (allCards.length === 0) {
      return json({ imported: 0, total: 0 });
    }

    // ── Find the set in DB (or use provided setId) ────────────────────────────
    let dbSetId = setId;
    if (!dbSetId) {
      const { data: s } = await supabase
        .from('sets')
        .select('id')
        .eq('cardsight_id', cardsightSetId)
        .single();
      dbSetId = s?.id;
    }

    if (!dbSetId) {
      return json({ error: 'Set not found in DB. Import the set first via catalog-import-sets.' }, 400);
    }

    // ── Deduplicate cards by (player, card_number) ────────────────────────────
    // Merge attributes with OR logic (never remove a flag)
    const cardMap = new Map<string, {
      player: string;
      cardNumber: string;
      isRookie: boolean;
      isAuto: boolean;
      isPatch: boolean;
      isSSP: boolean;
      imageUrl: string | null;
      cardsightCardId: string;
    }>();

    // First pass: deduplicate by name|number
    for (const card of allCards) {
      if (!card.name || card.name.trim() === '') continue;

      const attrs = (card.attributes ?? []).map(a => a.toUpperCase());
      const key = `${card.name}|${card.number}`;
      const existing = cardMap.get(key);

      if (existing) {
        existing.isRookie = existing.isRookie || attrs.includes('RC');
        existing.isAuto = existing.isAuto || attrs.includes('AU');
        existing.isPatch = existing.isPatch || attrs.includes('GU');
        existing.isSSP = existing.isSSP || attrs.includes('SSP');
      } else {
        cardMap.set(key, {
          player: card.name.trim(),
          cardNumber: card.number,
          isRookie: attrs.includes('RC'),
          isAuto: attrs.includes('AU'),
          isPatch: attrs.includes('GU'),
          isSSP: attrs.includes('SSP'),
          imageUrl: null,
          cardsightCardId: card.id,
        });
      }
    }

    // Second pass: fetch images from CardSight, upload to Storage, save URL
    for (const card of cardMap.values()) {
      try {
        const imgUrl = `${CARDSIGHT_BASE}/v1/images/cards/${card.cardsightCardId}`;

        const imgRes = await fetch(imgUrl, {
          headers: { 'X-Api-Key': apiKey },
        });

        if (imgRes.ok) {
          const imageBuffer = await imgRes.arrayBuffer();
          const fileName = `${card.cardsightCardId}.jpg`;

          const { data, error: uploadError } = await supabase.storage
            .from('cards')
            .upload(fileName, imageBuffer, {
              contentType: 'image/jpeg',
              upsert: true,
            });

          if (!uploadError && data) {
            const { data: urlData } = supabase.storage
              .from('cards')
              .getPublicUrl(fileName);
            card.imageUrl = urlData.publicUrl;
          }
        }
      } catch (_e) {
        // Silently skip image fetch errors
      }
      // Small delay to avoid rate-limiting
      await new Promise(r => setTimeout(r, 100));
    }

    // ── Upsert cards to master_card_definitions ───────────────────────────────
    const rows = Array.from(cardMap.values()).map(card => ({
      set_id:            dbSetId,
      player:            card.player,
      card_number:       card.cardNumber || null,
      serial_max:        null,
      is_rookie:         card.isRookie,
      is_auto:           card.isAuto,
      is_patch:          card.isPatch,
      is_ssp:            card.isSSP,
      image_url:         card.imageUrl,
      cardsight_card_id: card.cardsightCardId,
    }));

    const { data: upserted, error: upsertError } = await supabase
      .from('master_card_definitions')
      .upsert(rows)
      .select('id');

    if (upsertError) throw new Error(upsertError.message);

    return json({
      imported: upserted?.length ?? 0,
      total: cardMap.size,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-import-cards]', msg);
    return json({ error: msg }, 500);
  }
});
