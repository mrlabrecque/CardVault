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

/** Prefer `Base`, else lowest sort_order / name. */
function pickBaseParallelId(
  rows: { id: string; name: string; sort_order: number | null }[],
): string | null {
  if (!rows.length) return null;
  const sorted = [...rows].sort((a, b) => {
    const ab = a.name.trim().toLowerCase() === 'base' ? 0 : 1;
    const bb = b.name.trim().toLowerCase() === 'base' ? 0 : 1;
    if (ab !== bb) return ab - bb;
    const sa = a.sort_order ?? 999999;
    const sb = b.sort_order ?? 999999;
    if (sa !== sb) return sa - sb;
    return a.name.localeCompare(b.name);
  });
  return sorted[0]?.id ?? null;
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
      await new Promise(r => setTimeout(r, 250));
    }

    if (allCards.length === 0) {
      return json({ imported: 0, total: 0 });
    }

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

    const { data: parallelRows, error: parErr } = await supabase
      .from('set_parallels')
      .select('id, name, sort_order')
      .eq('set_id', dbSetId);

    if (parErr) throw new Error(parErr.message);

    const baseParallelId = pickBaseParallelId(parallelRows ?? []);
    if (!baseParallelId) {
      return json({ error: 'No parallels defined for this set; add parallels before importing cards.' }, 400);
    }

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
      await new Promise(r => setTimeout(r, 100));
    }

    const setRows = Array.from(cardMap.values()).map(card => ({
      set_id: dbSetId,
      player: card.player,
      card_number: card.cardNumber || null,
      is_rookie: card.isRookie,
      image_url: card.imageUrl,
      cardsight_card_id: card.cardsightCardId,
    }));

    const { data: upsertedSetCards, error: setErr } = await supabase
      .from('set_cards')
      .upsert(setRows, { onConflict: 'cardsight_card_id' })
      .select('id, cardsight_card_id');

    if (setErr) throw new Error(setErr.message);

    const byCsId = new Map((upsertedSetCards ?? []).map((r: { id: string; cardsight_card_id: string }) =>
      [r.cardsight_card_id, r.id] as const
    ));

    const variantRows = Array.from(cardMap.values()).map(card => {
      const setCardId = byCsId.get(card.cardsightCardId);
      if (!setCardId) return null;
      return {
        set_card_id: setCardId,
        parallel_id: baseParallelId,
        is_auto: card.isAuto,
        is_patch: card.isPatch,
        is_ssp: card.isSSP,
        serial_max: null as number | null,
      };
    }).filter(Boolean) as {
      set_card_id: string;
      parallel_id: string;
      is_auto: boolean;
      is_patch: boolean;
      is_ssp: boolean;
      serial_max: number | null;
    }[];

    const { error: varErr } = await supabase
      .from('master_card_definitions')
      .upsert(variantRows, { onConflict: 'set_card_id,parallel_id' });

    if (varErr) throw new Error(varErr.message);

    return json({
      imported: upsertedSetCards?.length ?? 0,
      total: cardMap.size,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-import-cards]', msg);
    return json({ error: msg }, 500);
  }
});
