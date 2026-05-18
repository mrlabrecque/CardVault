/**
 * Proxies upstream **card-search** only (no card-match):
 * POST https://api.cardhedger.com/v1/cards/card-search
 *
 * Upstream body: `category`, `page`, `page_size`, and `search` where
 * search = Player + Year + Release + #Number + Set. Parallel resolved from `variant` after fetch.
 * **Non-Base** parallels: [parallelExactCatalogVariant] on `variant` (`&` → `and`);
 * if no exact row, [parallelDescriptionWordMatch] on `description` (all parallel words,
 * rookie/rookies tolerant). **Base** uses [pickBestBaseVariantRow]; fuzzy [parallelScore]
 * only when Base has zero exact rows.
 * If the chosen row has no persistable `prices`, calls all-prices-by-card before
 * persist and response `match`.
 */
import {
  buildCardHedgeCardSearchBody,
  buildCardHedgeCardSearchString,
  cardNumberMatches,
  catalogParallelImpliesBase,
  categoryFromSport,
  insertSetMatchesDescription,
  normLabel,
  parallelExactCatalogVariant,
  parallelDescriptionWordMatch,
  parallelScore,
  extractCardHedgeSalesFromRow,
  pickBestAmongExactVariantRows,
  pickBestBaseVariantRow,
  stripSerialSuffix,
} from '../_shared/cardhedge_text.ts';
import {
  type CatalogMasterSnapshot,
  fetchCatalogMasterSnapshot,
  normalizePriceEntry,
  persistGuidePricesOntoMaster,
} from '../_shared/cardhedge_persist_master.ts';
import { fetchCardHedgeAllLatestPrices } from '../_shared/cardhedge_all_prices.ts';
import { verifyUserJwt } from '../_shared/supabase_user_jwt.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const CARD_SEARCH_URL = 'https://api.cardhedger.com/v1/cards/card-search';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function parseMinConfidence(): number {
  const raw = Deno.env.get('CARDHEDGE_MATCH_MIN_CONFIDENCE')?.trim();
  if (!raw) return 0.9;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0 || n > 1) return 0.9;
  return n;
}

function parseMaxSearchPages(): number {
  const raw = Deno.env.get('CARDHEDGE_SEARCH_MAX_PAGES')?.trim();
  const n = raw ? parseInt(raw, 10) : 10;
  if (!Number.isFinite(n) || n < 1) return 10;
  return Math.min(20, n);
}

/** How many pre/post-filter rows to include in logs (default 25, max 80). */
function parseLogSampleLimit(): number {
  const raw = Deno.env.get('CARDHEDGE_SEARCH_LOG_SAMPLE')?.trim();
  const n = raw ? parseInt(raw, 10) : 25;
  if (!Number.isFinite(n) || n < 0) return 25;
  return Math.min(80, n);
}

const LOG_TAG = 'cardhedge-search-cards';

/** Echoed in API responses (debug) — vault params + exact CardHedge POST body for replay. */
function buildCardhedgeRequestDebug(input: {
  vaultToEdge: Record<string, unknown>;
  setLabel: string;
  upstreamPostBody: Record<string, unknown>;
}): Record<string, unknown> {
  return {
    vault_to_edge: input.vaultToEdge,
    cardhedge_api: {
      url: CARD_SEARCH_URL,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': '<set in Supabase secrets — not echoed>',
      },
    },
    cardhedge_post_body: input.upstreamPostBody,
    cardhedge_search_query: input.setLabel,
  };
}

function clip(s: string, max: number): string {
  const t = s.replace(/\s+/g, ' ').trim();
  if (t.length <= max) return t;
  return `${t.slice(0, max)}…`;
}

function summarizeRow(row: Record<string, unknown>) {
  return {
    card_id: row.card_id,
    number: row.number,
    variant: row.variant,
    description: typeof row.description === 'string' ? clip(row.description, 100) : null,
  };
}

type RowSummary = ReturnType<typeof summarizeRow>;

function sampleRows(rows: Record<string, unknown>[], limit: number): {
  shown: number;
  total: number;
  rows: RowSummary[];
} {
  const n = Math.min(limit, rows.length);
  const out: RowSummary[] = [];
  for (let i = 0; i < n; i++) out.push(summarizeRow(rows[i]!));
  return { shown: n, total: rows.length, rows: out };
}

function strField(body: Record<string, unknown>, ...keys: string[]): string {
  for (const k of keys) {
    const v = body[k];
    if (typeof v === 'string' && v.trim()) return v.trim();
  }
  return '';
}

function searchRowToMatch(row: Record<string, unknown>) {
  const sales = extractCardHedgeSalesFromRow(row);
  return {
    card_id: row.card_id,
    description: row.description,
    player: row.player,
    set: row.set,
    number: row.number,
    variant: row.variant,
    category: row.category,
    image: row.image,
    prices: row.prices,
    reasoning: row.reasoning ?? null,
    sales_7d: sales.sales_7d,
    sales_30d: sales.sales_30d,
    gain: sales.gain,
  };
}

function rowHasPersistablePrices(row: Record<string, unknown>): boolean {
  const p = row.prices;
  if (!Array.isArray(p)) return false;
  for (const e of p) {
    if (normalizePriceEntry(e) !== null) return true;
  }
  return false;
}

/** When card-search omits usable `prices`, CardHedge docs recommend all-prices-by-card. */
async function ensureChosenRowHasPrices(
  chosen: Record<string, unknown>,
  apiKey: string,
  timeoutMs: number,
): Promise<Record<string, unknown>> {
  if (rowHasPersistablePrices(chosen)) return chosen;
  const id = String(chosen.card_id ?? '').trim();
  if (!id) return chosen;
  const backfill = await fetchCardHedgeAllLatestPrices(apiKey, id, { timeoutMs });
  if (!backfill || backfill.length === 0) {
    console.log(JSON.stringify({ tag: LOG_TAG, event: 'prices_backfill_empty', card_id: id }));
    return chosen;
  }
  console.log(
    JSON.stringify({
      tag: LOG_TAG,
      event: 'prices_backfill_all_prices',
      card_id: id,
      grade_rows: backfill.length,
    }),
  );
  return { ...chosen, prices: backfill };
}

Deno.serve(async (req) => {
  if (req.method !== 'OPTIONS') {
    console.log(JSON.stringify({ tag: LOG_TAG, event: 'request', method: req.method }));
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Unauthorized' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const userId = await verifyUserJwt(authHeader, supabaseUrl);
    if (!userId) return json({ error: 'Unauthorized' }, 401);

    const apiKey =
      Deno.env.get('CARDHEDGE_API_KEY')?.trim() ||
      Deno.env.get('CARDHEDGER_API_KEY')?.trim();
    if (!apiKey) {
      console.error(JSON.stringify({ tag: LOG_TAG, event: 'config_error', message: 'CARDHEDGE_API_KEY not set' }));
      return json(
        {
          error: 'CardHedge is not configured',
          hint:
            'Add secret CARDHEDGE_API_KEY in Supabase: Project Settings → Edge Functions → Secrets, then deploy cardhedge-search-cards.',
        },
        503,
      );
    }

    const body = (await req.json()) as Record<string, unknown>;
    const player = strField(body, 'player');
    if (!player) {
      return json({ error: 'player is required' }, 400);
    }

    const categoryExplicit = strField(body, 'category');
    const sport = strField(body, 'sport');
    const category = categoryExplicit || categoryFromSport(sport) || '';
    if (!category) {
      return json({ error: 'category or sport is required' }, 400);
    }

    const yearRaw = body.year ?? body.release_year;
    const year = typeof yearRaw === 'number' && Number.isFinite(yearRaw)
      ? Math.trunc(yearRaw)
      : typeof yearRaw === 'string' && /^\d{4}$/.test(yearRaw.trim())
      ? parseInt(yearRaw.trim(), 10)
      : null;

    const releaseName = strField(body, 'releaseName', 'release_name');
    if (!releaseName) {
      return json({ error: 'releaseName is required' }, 400);
    }
    const setName = strField(body, 'setName', 'set_name');
    const cardNumber = strField(body, 'cardNumber', 'card_number', 'number');
    const parallelNameRaw = strField(body, 'parallelName', 'parallel_name', 'parallel');
    const parallelName = parallelNameRaw ? stripSerialSuffix(parallelNameRaw) : '';
    const persistMasterVariantId = strField(body, 'persistMasterVariantId', 'persist_master_variant_id');

    const psRaw = body.page_size ?? body.pageSize;
    const pageSize = typeof psRaw === 'number' && Number.isInteger(psRaw)
      ? Math.min(100, Math.max(1, psRaw))
      : 100;

    const searchQuery = buildCardHedgeCardSearchString({
      player,
      year,
      releaseName,
      cardNumber: cardNumber || null,
      setName: setName || null,
    });

    if (searchQuery.length < 2) {
      return json(
        {
          error: 'Could not build CardHedge search string (need player + year/release/set)',
          details: { year, releaseName, setName: setName || null, player },
        },
        400,
      );
    }

    const minConfidence = parseMinConfidence();
    const maxPages = parseMaxSearchPages();

    const rookieRaw = strField(body, 'rookie');
    const rookie =
      rookieRaw ||
      (body.is_rookie === true || body.isRookie === true ? 'Rookie' : '');
    const upstreamBase = buildCardHedgeCardSearchBody({
      category,
      player,
      year,
      releaseName,
      setName: setName || null,
      cardNumber: cardNumber || null,
      pageSize,
      page: 1,
      rawImagesOnly: true,
      rookie: rookie || null,
    });
    // Drop page from base — loop adds per-page `page`.
    const { page: _dropPage, ...upstreamBaseNoPage } = upstreamBase;

    const cardhedgeRequestDebug = buildCardhedgeRequestDebug({
      vaultToEdge: {
        player,
        year,
        releaseName,
        setName: setName || null,
        cardNumber: cardNumber || null,
        parallelName: parallelName || null,
        category,
        sport: sport || null,
        page_size: pageSize,
        persistMasterVariantId: persistMasterVariantId || null,
      },
      setLabel: searchQuery,
      upstreamPostBody: upstreamBase,
    });

    const logSample = parseLogSampleLimit();

    const seenIds = new Set<string>();
    const allCards: Record<string, unknown>[] = [];
    let totalPages = 1;
    let upstreamCount = 0;
    let pagesScanned = 0;

    const perReqTimeoutMs = 20_000;

    for (let pageNum = 1; pageNum <= totalPages && pageNum <= maxPages; pageNum++) {
      const requestBody = { ...upstreamBaseNoPage, page: pageNum };
      const requestBodyString = JSON.stringify(requestBody);

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), perReqTimeoutMs);
      let upstream: Response;
      try {
        upstream = await fetch(CARD_SEARCH_URL, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': apiKey,
          },
          body: requestBodyString,
          signal: controller.signal,
        });
      } catch (e) {
        if (e instanceof DOMException && e.name === 'AbortError') {
          console.error(JSON.stringify({ tag: LOG_TAG, event: 'upstream_timeout', page: pageNum }));
          return json({ error: 'CardHedge request timed out' }, 504);
        }
        throw e;
      } finally {
        clearTimeout(timeout);
      }

      const text = await upstream.text();
      if (!upstream.ok) {
        console.error(
          JSON.stringify({
            tag: LOG_TAG,
            event: 'upstream_http_error',
            status: upstream.status,
            body_preview: clip(text, 400),
          }),
        );
        return json(
          {
            error: 'CardHedge search failed',
            status: upstream.status,
            details: text.slice(0, 2000),
            cardhedge_request: cardhedgeRequestDebug,
          },
          502,
        );
      }

      let data: Record<string, unknown>;
      try {
        data = JSON.parse(text) as Record<string, unknown>;
      } catch {
        return json({ error: 'Invalid JSON from CardHedge' }, 502);
      }

      if (pageNum === 1) {
        upstreamCount = typeof data.count === 'number' ? data.count : 0;
        const p = typeof data.pages === 'number' && data.pages >= 1 ? data.pages : 1;
        totalPages = p;
      }

      const cardsRaw = data.cards;
      const batch = Array.isArray(cardsRaw)
        ? (cardsRaw as unknown[]).filter((c): c is Record<string, unknown> => c !== null && typeof c === 'object')
        : [];

      for (const row of batch) {
        const id = String(row.card_id ?? '');
        if (!id || seenIds.has(id)) continue;
        seenIds.add(id);
        allCards.push(row);
      }

      pagesScanned = pageNum;
      if (batch.length === 0) break;
    }

    console.log(
      JSON.stringify({
        tag: LOG_TAG,
        event: 'prefilter',
        userId,
        request: {
          category,
          year,
          release_name: releaseName,
          set_name: setName || null,
          search: searchQuery,
          player,
          card_number: cardNumber || null,
          parallel: parallelName || null,
          page_size: pageSize,
          max_pages: maxPages,
        },
        upstream: {
          total_count: upstreamCount,
          total_pages_reported: totalPages,
          pages_scanned: pagesScanned,
          unique_cards_accumulated: allCards.length,
        },
        prefilter_sample: sampleRows(allCards, logSample),
      }),
    );

    const byNumber = allCards.filter((row) => cardNumberMatches(cardNumber || null, row.number));

    console.log(
      JSON.stringify({
        tag: LOG_TAG,
        event: 'after_card_number',
        card_number_filter: cardNumber || null,
        count: byNumber.length,
        sample: sampleRows(byNumber, logSample),
      }),
    );

    const byInsertSet = byNumber.filter((row) => insertSetMatchesDescription(setName || null, row));

    console.log(
      JSON.stringify({
        tag: LOG_TAG,
        event: 'after_insert_set',
        set_name_filter: setName || null,
        count: byInsertSet.length,
        sample: sampleRows(byInsertSet, logSample),
      }),
    );

    if (byNumber.length === 0) {
      console.log(JSON.stringify({ tag: LOG_TAG, event: 'outcome', matched: false, reason: allCards.length === 0 ? 'no_match' : 'no_rows_after_number_filter' }));
      return json({
        matched: false,
        minConfidence,
        reason: allCards.length === 0 ? 'no_match' : 'search_no_row_after_filter',
        confidence: null,
        resolved_via: 'card_search',
        search_set: searchQuery,
        search_meta: {
          page_size: pageSize,
          max_pages_scanned: maxPages,
          total_pages_reported: totalPages,
          upstream_count: upstreamCount,
          cards_accumulated: allCards.length,
          after_number_filter: 0,
          after_insert_set_filter: 0,
        },
        expected_parallel: parallelName ? stripSerialSuffix(parallelName) : null,
        card_number: cardNumber || null,
        cardhedge_request: cardhedgeRequestDebug,
      });
    }

    if (byInsertSet.length === 0) {
      console.log(JSON.stringify({ tag: LOG_TAG, event: 'outcome', matched: false, reason: 'no_rows_after_insert_set_filter' }));
      return json({
        matched: false,
        minConfidence,
        reason: 'search_no_row_after_filter',
        confidence: null,
        resolved_via: 'card_search',
        search_set: searchQuery,
        search_meta: {
          page_size: pageSize,
          max_pages_scanned: maxPages,
          total_pages_reported: totalPages,
          upstream_count: upstreamCount,
          cards_accumulated: allCards.length,
          after_number_filter: byNumber.length,
          after_insert_set_filter: 0,
        },
        expected_parallel: parallelName ? stripSerialSuffix(parallelName) : null,
        card_number: cardNumber || null,
        cardhedge_request: cardhedgeRequestDebug,
      });
    }

    let chosen: Record<string, unknown> | null = null;
    let alternateRows: Record<string, unknown>[] = [];
    let parallelMatchMode:
      | 'exact_variant'
      | 'base_auto_pick'
      | 'fuzzy_best_no_alternates'
      | 'description_word_match'
      | 'parallel_unspecified' = 'parallel_unspecified';
    let afterParallelExact = 0;

    if (!parallelName) {
      const picked = pickBestBaseVariantRow(byInsertSet, setName || null);
      chosen = picked.chosen;
      alternateRows = picked.alternates;
      parallelMatchMode = 'base_auto_pick';
    } else {
      const exactPool = byInsertSet.filter((row) => parallelExactCatalogVariant(parallelName, row));
      if (exactPool.length > 0) {
        afterParallelExact = exactPool.length;
        if (catalogParallelImpliesBase(parallelName)) {
          const picked = pickBestBaseVariantRow(exactPool, setName || null);
          chosen = picked.chosen;
          alternateRows = picked.alternates;
          parallelMatchMode = 'base_auto_pick';
        } else {
          const picked = pickBestAmongExactVariantRows(exactPool);
          chosen = picked.chosen;
          alternateRows = picked.alternates;
          parallelMatchMode = 'exact_variant';
        }
      } else if (catalogParallelImpliesBase(parallelName)) {
        const ranked = [...byInsertSet].sort(
          (a, b) => parallelScore(parallelName, b) - parallelScore(parallelName, a),
        );
        const top = ranked[0] as Record<string, unknown>;
        const topScore = parallelScore(parallelName, top);
        if (topScore < 15) {
          console.log(
            JSON.stringify({
              tag: LOG_TAG,
              event: 'outcome',
              matched: false,
              reason: 'no_exact_and_fuzzy_below_threshold',
              best_fuzzy_parallel_score: topScore,
              threshold: 15,
            }),
          );
          return json({
            matched: false,
            minConfidence,
            reason: 'search_no_row_after_filter',
            confidence: null,
            resolved_via: 'card_search',
            search_set: searchQuery,
            search_meta: {
              page_size: pageSize,
              max_pages_scanned: maxPages,
              total_pages_reported: totalPages,
              upstream_count: upstreamCount,
              cards_accumulated: allCards.length,
              after_number_filter: byNumber.length,
              after_insert_set_filter: byInsertSet.length,
              after_parallel_exact_filter: 0,
              best_fuzzy_parallel_score: topScore,
            },
            expected_parallel: stripSerialSuffix(parallelName),
            card_number: cardNumber || null,
            cardhedge_request: cardhedgeRequestDebug,
          });
        }
        chosen = top;
        alternateRows = [];
        parallelMatchMode = 'fuzzy_best_no_alternates';
      } else {
        const descPool = byInsertSet.filter((row) =>
          parallelDescriptionWordMatch(parallelName, row)
        );
        if (descPool.length > 0) {
          const picked = pickBestAmongExactVariantRows(descPool);
          chosen = picked.chosen;
          alternateRows = picked.alternates;
          parallelMatchMode = 'description_word_match';
          console.log(
            JSON.stringify({
              tag: LOG_TAG,
              event: 'parallel_description_word_match',
              expected_parallel: stripSerialSuffix(parallelName),
              pool_size: descPool.length,
            }),
          );
        } else {
          console.log(
            JSON.stringify({
              tag: LOG_TAG,
              event: 'outcome',
              matched: false,
              reason: 'no_exact_parallel_match',
              expected_parallel: stripSerialSuffix(parallelName),
            }),
          );
          return json({
            matched: false,
            minConfidence,
            reason: 'no_exact_parallel_match',
            confidence: null,
            resolved_via: 'card_search',
            search_set: searchQuery,
            search_meta: {
              page_size: pageSize,
              max_pages_scanned: maxPages,
              total_pages_reported: totalPages,
              upstream_count: upstreamCount,
              cards_accumulated: allCards.length,
              after_number_filter: byNumber.length,
              after_insert_set_filter: byInsertSet.length,
              after_parallel_exact_filter: 0,
              after_parallel_description_filter: 0,
              parallel_match: 'exact_required_non_base',
            },
            expected_parallel: stripSerialSuffix(parallelName),
            card_number: cardNumber || null,
            cardhedge_request: cardhedgeRequestDebug,
          });
        }
      }
    }

    const alternate_matches = alternateRows.map((r) => searchRowToMatch(r));

    const confidence = 1.0;

    if (!chosen) {
      console.error(JSON.stringify({ tag: LOG_TAG, event: 'internal', message: 'chosen_unset_after_filter' }));
      return json({ error: 'Internal error' }, 500);
    }

    chosen = await ensureChosenRowHasPrices(chosen, apiKey, perReqTimeoutMs);

    console.log(
      JSON.stringify({
        tag: LOG_TAG,
        event: 'outcome',
        matched: true,
        chosen: summarizeRow(chosen),
        parallel_match: parallelMatchMode,
        alternate_count: alternate_matches.length,
        persist_master_variant_id: persistMasterVariantId || null,
      }),
    );

    let persisted_master: CatalogMasterSnapshot | null = null;
    if (persistMasterVariantId) {
      const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim();
      if (serviceKey) {
        try {
          const admin = createClient(supabaseUrl, serviceKey);
          const matchOut = searchRowToMatch(chosen);
          await persistGuidePricesOntoMaster(admin, {
            masterVariantId: persistMasterVariantId,
            guidePriceCardId: typeof matchOut.card_id === 'string' ? matchOut.card_id : undefined,
            imageUrl: typeof matchOut.image === 'string' ? matchOut.image : null,
            prices: Array.isArray(matchOut.prices) ? (matchOut.prices as unknown[]) : undefined,
            sales7d: matchOut.sales_7d,
            sales30d: matchOut.sales_30d,
            gain: matchOut.gain,
          });
          persisted_master = await fetchCatalogMasterSnapshot(admin, persistMasterVariantId);
        } catch (e) {
          console.error(
            JSON.stringify({ tag: LOG_TAG, event: 'persist_inline_failed', message: String(e) }),
          );
        }
      }
    }

    return json({
      matched: true,
      minConfidence,
      confidence,
      resolved_via: 'card_search',
            search_set: searchQuery,
      search_meta: {
        page_size: pageSize,
        max_pages_scanned: maxPages,
        total_pages_reported: totalPages,
        upstream_count: upstreamCount,
        cards_accumulated: allCards.length,
        after_number_filter: byNumber.length,
        after_insert_set_filter: byInsertSet.length,
        after_parallel_exact_filter: afterParallelExact,
        parallel_match: parallelMatchMode,
        alternate_count: alternate_matches.length,
      },
      match: searchRowToMatch(chosen),
      alternate_matches,
      cardhedge_request: cardhedgeRequestDebug,
      ...(persistMasterVariantId ? { persisted_master } : {}),
    });
  } catch (e) {
    console.error(JSON.stringify({ tag: LOG_TAG, event: 'exception', message: String(e) }));
    return json({ error: 'Internal server error', details: String(e) }, 500);
  }
});
