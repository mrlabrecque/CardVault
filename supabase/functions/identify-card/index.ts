/**
 * Vision identify: CardSight, CardHedge image-search, or both (single HTTP from the app).
 *
 * Strategy (body `identifyStrategy` or env `SCAN_IDENTIFY_STRATEGY`):
 * - `auto` (default): both keys → **CardHedge image-search first**, then CardSight; merge CH
 *   (parallel images + ids) onto CardSight detections. Else whichever API is configured.
 * - `cardsight`: CardSight only.
 * - `cardhedge`: CardHedge image-search only (no CardSight bill; no CardSight UUIDs on card).
 * - `merge`: same as auto when both configured; falls back if one key missing.
 *
 * Optional body: `cardhedgeK` (1–50, default 12) — max image-search results.
 * Optional body: `enrichChCandidates` (boolean, default false) — when true with CardHedge hits,
 * attaches guide `prices` + CardSight `cardsightReleaseId` / `cardsightSetId` spine hints per candidate
 * (requires `SUPABASE_SERVICE_ROLE_KEY` + `CARDSIGHT_API_KEY` for spine resolution).
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  applyChEnrichedSpineToMergedDetections,
  chHitsToJsonCandidates,
  detectionsFromChHitsOnly,
  fetchCardHedgeImageSearchHits,
  mergeChHitsIntoCardSightDetections,
  type ChImageHit,
} from '../_shared/scan_identify_merge.ts';
import {
  batchEnrichChCandidatesWithPrices,
  enrichChCandidatesFull,
} from '../_shared/identify_ch_candidate_enrich.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function cardHedgeKey(): string | null {
  return (
    Deno.env.get('CARDHEDGE_API_KEY')?.trim() ||
    Deno.env.get('CARDHEDGER_API_KEY')?.trim() ||
    null
  );
}

function readEnrichChCandidates(body: Record<string, unknown>): boolean {
  const v = body.enrichChCandidates ?? body.enrich_ch_candidates;
  return v === true || v === 'true' || v === 1;
}

async function maybeEnrichChCandidates(
  body: Record<string, unknown>,
  sport: string,
  mode: 'cardhedge' | 'merge',
  chKey: string,
  hits: ChImageHit[],
  chK: number,
): Promise<Record<string, unknown>[] | null> {
  if (!readEnrichChCandidates(body)) return null;
  if (hits.length === 0) return null;
  const candidates = chHitsToJsonCandidates(hits, Math.min(50, chK));
  const srk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim();
  const csApi = Deno.env.get('CARDSIGHT_API_KEY')?.trim();
  const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim();
  if (srk && csApi && supabaseUrl) {
    const supabase = createClient(supabaseUrl, srk);
    await enrichChCandidatesFull(
      { supabase, cardsightApiKey: csApi, cardHedgeApiKey: chKey, sportSlug: sport },
      candidates,
    );
  } else {
    await batchEnrichChCandidatesWithPrices(chKey, candidates);
  }
  return candidates;
}

type Strategy = 'auto' | 'cardsight' | 'cardhedge' | 'merge';

function resolveStrategy(body: Record<string, unknown>): Strategy {
  const raw = String(body.identifyStrategy ?? body.strategy ?? Deno.env.get('SCAN_IDENTIFY_STRATEGY') ?? 'auto')
    .trim()
    .toLowerCase();
  if (raw === 'cardsight' || raw === 'cardhedge' || raw === 'merge') return raw;
  return 'auto';
}

function effectiveMode(strat: Strategy, hasCs: boolean, hasCh: boolean): 'cardsight' | 'cardhedge' | 'merge' {
  if (strat === 'cardsight') return 'cardsight';
  if (strat === 'cardhedge') return 'cardhedge';
  if (strat === 'merge') {
    if (hasCs && hasCh) return 'merge';
    if (hasCh) return 'cardhedge';
    return 'cardsight';
  }
  // auto
  if (hasCs && hasCh) return 'merge';
  if (hasCh) return 'cardhedge';
  return 'cardsight';
}

async function cardSightIdentify(imageBase64: string, sport: string): Promise<Record<string, unknown>> {
  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) {
    throw new Error('CARDSIGHT_API_KEY not set');
  }
  const binaryString = atob(imageBase64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  const formData = new FormData();
  const blob = new Blob([bytes], { type: 'image/jpeg' });
  formData.append('file', blob, 'card.jpg');

  const url = `https://api.cardsight.ai/v1/identify/card/${sport}`;
  const controller = new AbortController();
  const timeoutMs = 60000;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let response: Response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { 'X-Api-Key': apiKey },
      body: formData,
      signal: controller.signal,
    });
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw new Error('CardSight request timed out');
    }
    throw err;
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`CardSight error: ${response.status} ${errorText}`);
  }
  return (await response.json()) as Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    });
  }

  try {
    const body = (await req.json()) as Record<string, unknown>;
    const imageBase64 = body?.imageBase64;
    const sport = typeof body?.sport === 'string' && body.sport.trim() ? body.sport.trim() : 'baseball';

    if (!imageBase64 || typeof imageBase64 !== 'string') {
      return json({ error: 'imageBase64 is required' }, 400);
    }

    const b64 = imageBase64.trim();
    const chKRaw = body.cardhedgeK ?? body.cardhedge_k;
    let chK = typeof chKRaw === 'number' && Number.isFinite(chKRaw) ? Math.trunc(chKRaw) : 12;
    if (chK < 1) chK = 1;
    if (chK > 50) chK = 50;

    const hasCs = !!Deno.env.get('CARDSIGHT_API_KEY');
    const chKey = cardHedgeKey();
    const hasCh = !!chKey;
    const strat = resolveStrategy(body);
    const mode = effectiveMode(strat, hasCs, hasCh);

    if (mode === 'cardsight' && !hasCs) {
      return json({ error: 'CardSight is not configured (CARDSIGHT_API_KEY missing)' }, 500);
    }
    if (mode === 'cardhedge' && !hasCh) {
      return json({ error: 'CardHedge is not configured (CARDHEDGE_API_KEY missing)' }, 503);
    }
    if (mode === 'merge' && (!hasCs || !hasCh)) {
      return json({ error: 'Merge mode requires both CARDSIGHT_API_KEY and CARDHEDGE_API_KEY' }, 500);
    }

    let result: Record<string, unknown>;

    if (mode === 'cardsight') {
      result = await cardSightIdentify(b64, sport);
      result.identify_mode = 'cardsight';
      result.identify_strategy_requested = strat;
      const dets = result.detections;
      if (Array.isArray(dets)) {
        for (const el of dets) {
          if (el && typeof el === 'object') {
            (el as Record<string, unknown>).vision_merge_debug = {
              strategy: 'cardsight_only',
              note:
                'CardHedge image-search was not run. Set body.identifyStrategy to "merge" or "cardhedge", or env SCAN_IDENTIFY_STRATEGY, to include CardHedge.',
            };
          }
        }
      }
    } else if (mode === 'cardhedge') {
      const hits = await fetchCardHedgeImageSearchHits(chKey!, b64, chK);
      const enriched = await maybeEnrichChCandidates(body, sport, 'cardhedge', chKey!, hits, chK);
      const dets = detectionsFromChHitsOnly(hits, sport);
      result = {
        success: dets.length > 0,
        detections: dets,
        identify_mode: 'cardhedge',
        identify_strategy_requested: strat,
        cardhedge_candidates: enriched ?? chHitsToJsonCandidates(hits, chK),
        cardhedge_hits_sample: hits.slice(0, 12),
      };
    } else {
      // merge: CardHedge first (variant / parallel imagery), then CardSight for catalog UUIDs.
      const hits = await fetchCardHedgeImageSearchHits(chKey!, b64, chK);
      const enriched = await maybeEnrichChCandidates(body, sport, 'merge', chKey!, hits, chK);
      result = await cardSightIdentify(b64, sport);
      const rawDets = result.detections;
      const dets = Array.isArray(rawDets)
        ? rawDets.filter((x): x is Record<string, unknown> => x != null && typeof x === 'object')
        : [];
      mergeChHitsIntoCardSightDetections(dets, hits);
      applyChEnrichedSpineToMergedDetections(enriched, dets);
      result.detections = dets;
      result.identify_mode = 'merge';
      result.identify_strategy_requested = strat;
      result.cardhedge_candidates = enriched ?? chHitsToJsonCandidates(hits, 25);
      result.cardhedge_hits_sample = hits.slice(0, 12);
      result.vision_upstream_order = ['cardhedge_image_search', 'cardsight_identify'];
    }

    const dlen = Array.isArray(result.detections) ? (result.detections as unknown[]).length : 0;
    console.log('[identify-card] mode:', mode, 'strategy:', strat, 'detections:', dlen);

    return json(result, 200);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[identify-card] exception:', msg);
    if (msg.includes('timed out')) {
      return json({ error: 'Identification timed out', details: msg }, 504);
    }
    return json({ error: 'Internal server error', details: msg }, 500);
  }
});
