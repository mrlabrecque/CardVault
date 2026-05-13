/**
 * Proxies upstream **card-search** only (no card-match):
 * POST https://api.cardhedger.com/v1/cards/card-search
 *
 * Structured body only (no `search` field — parallel is resolved from `variant`
 * after fetch). Upstream `set` = year (if not already on release) + releaseName +
 * category; subset (Fireworks, …) on `description`, parallel on `variant`.
 * `alternate_matches` only for **exact** normalized `variant` ties. If none match
 * exactly, a **single** best row is chosen via [parallelScore] (persist + prices)
 * with `alternate_matches: []` so the app does not show fuzzy parallel chips.
 * If the chosen row has no persistable `prices`, calls all-prices-by-card before
 * persist and response `match`.
 */
import {
  buildCardHedgeSearchSetLabel,
  cardNumberMatches,
  categoryFromSport,
  insertSetMatchesDescription,
  normLabel,
  parallelExactCatalogVariant,
  parallelScore,
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

/** CardHedge rows may use spaced keys; expose stable names for clients + persist. */
function extractCardHedgeSales(row: Record<string, unknown>): {
  sales_7d: number | null;
  sales_30d: number | null;
  gain: number | null;
} {
  const toNum = (v: unknown): number | null => {
    if (typeof v === 'number' && Number.isFinite(v)) return v;
    if (typeof v === 'string') {
      const n = parseFloat(v.replace(/[^0-9.-]/g, ''));
      return Number.isFinite(n) ? n : null;
    }
    return null;
  };
  const pick = (...keys: string[]): number | null => {
    for (const k of keys) {
      if (Object.prototype.hasOwnProperty.call(row, k)) {
        const n = toNum(row[k]);
        if (n !== null) return n;
      }
    }
    return null;
  };
  return {
    sales_7d: pick('7 Day Sales', '7_Day_Sales', 'sales_7d', 'seven_day_sales', 'sevenDaySales'),
    sales_30d: pick('30 Day Sales', '30_Day_Sales', 'sales_30d', 'thirty_day_sales', 'thirtyDaySales'),
    gain: pick('gain', 'Gain'),
  };
}

function searchRowToMatch(row: Record<string, unknown>) {
  const sales = extractCardHedgeSales(row);
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

/** Rows the app can show so you can compare catalog parallel vs CardHedge `variant` strings. */
function buildParallelDebugPayload(input: {
  requested_parallel: string;
  after_number_count: number;
  after_insert_set_count: number;
  rows: Record<string, unknown>[];
  row_limit?: number;
  match_mode?: string | null;
}): Record<string, unknown> {
  const lim = input.row_limit ?? 120;
  const rows: Record<string, unknown>[] = [];
  for (let i = 0; i < Math.min(lim, input.rows.length); i++) {
    const r = input.rows[i]!;
    const n = r.number;
    rows.push({
      card_id: typeof r.card_id === 'string' ? r.card_id : null,
      number: n === null || n === undefined ? null : String(n),
      variant: typeof r.variant === 'string' ? r.variant : null,
    });
  }
  const out: Record<string, unknown> = {
    requested_parallel: input.requested_parallel || null,
    after_number_count: input.after_number_count,
    after_insert_set_count: input.after_insert_set_count,
    variant_rows_shown: rows.length,
    rows,
  };
  if (input.match_mode != null && input.match_mode !== '') {
    out.match_mode = input.match_mode;
  }
  return out;
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

    const setLabel = buildCardHedgeSearchSetLabel({
      year,
      releaseName,
      category,
    });

    if (setLabel.length < 2) {
      return json(
        { error: 'Could not build set label from year/release/category', details: { year, releaseName, category } },
        400,
      );
    }

    const minConfidence = parseMinConfidence();
    const maxPages = parseMaxSearchPages();

    const upstreamBase: Record<string, unknown> = {
      category,
      page_size: pageSize,
      set: setLabel,
      player,
    };

    const logSample = parseLogSampleLimit();

    const seenIds = new Set<string>();
    const allCards: Record<string, unknown>[] = [];
    let totalPages = 1;
    let upstreamCount = 0;
    let pagesScanned = 0;

    const perReqTimeoutMs = 20_000;

    for (let pageNum = 1; pageNum <= totalPages && pageNum <= maxPages; pageNum++) {
      const requestBody = { ...upstreamBase, page: pageNum };
      const requestBodyString = JSON.stringify(requestBody);
      // Exact POST JSON CardHedge receives (API key is only in headers, never logged here).
      console.log(
        JSON.stringify({
          tag: LOG_TAG,
          event: 'cardhedge_upstream_post_body',
          url: CARD_SEARCH_URL,
          page: pageNum,
          json: requestBody,
          json_string: requestBodyString,
        }),
      );

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
          { error: 'CardHedge search failed', status: upstream.status, details: text.slice(0, 2000) },
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
          set: setLabel,
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
        search_set: setLabel,
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
        parallel_debug: buildParallelDebugPayload({
          requested_parallel: parallelName,
          after_number_count: 0,
          after_insert_set_count: 0,
          rows: allCards,
        }),
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
        search_set: setLabel,
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
        parallel_debug: buildParallelDebugPayload({
          requested_parallel: parallelName,
          after_number_count: byNumber.length,
          after_insert_set_count: 0,
          rows: byNumber,
        }),
      });
    }

    const MIN_NONBASE_PARALLEL_SCORE = 22;

    let chosen: Record<string, unknown> | null = null;
    let alternateRows: Record<string, unknown>[] = [];
    let parallelMatchMode: 'exact_variant' | 'fuzzy_best_no_alternates' | 'parallel_unspecified' =
      'parallel_unspecified';
    let afterParallelExact = 0;

    if (!parallelName) {
      const sorted = [...byInsertSet].sort((a, b) =>
        String(a.card_id ?? '').localeCompare(String(b.card_id ?? ''))
      );
      chosen = sorted[0] as Record<string, unknown>;
      alternateRows = sorted.slice(1).slice(0, 24);
      parallelMatchMode = 'parallel_unspecified';
    } else {
      const exactPool = byInsertSet.filter((row) => parallelExactCatalogVariant(parallelName, row));
      if (exactPool.length > 0) {
        afterParallelExact = exactPool.length;
        const sorted = [...exactPool].sort((a, b) =>
          String(a.card_id ?? '').localeCompare(String(b.card_id ?? ''))
        );
        chosen = sorted[0] as Record<string, unknown>;
        alternateRows = sorted.slice(1).slice(0, 24);
        parallelMatchMode = 'exact_variant';
      } else {
        const ranked = [...byInsertSet].sort(
          (a, b) => parallelScore(parallelName, b) - parallelScore(parallelName, a),
        );
        const top = ranked[0] as Record<string, unknown>;
        const topScore = parallelScore(parallelName, top);
        const expN = normLabel(stripSerialSuffix(parallelName));
        const minScore = !expN || expN === 'base' ? 15 : MIN_NONBASE_PARALLEL_SCORE;
        if (topScore < minScore) {
          console.log(
            JSON.stringify({
              tag: LOG_TAG,
              event: 'outcome',
              matched: false,
              reason: 'no_exact_and_fuzzy_below_threshold',
              best_fuzzy_parallel_score: topScore,
              threshold: minScore,
            }),
          );
          return json({
            matched: false,
            minConfidence,
            reason: 'search_no_row_after_filter',
            confidence: null,
            resolved_via: 'card_search',
            search_set: setLabel,
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
            parallel_debug: buildParallelDebugPayload({
              requested_parallel: parallelName,
              after_number_count: byNumber.length,
              after_insert_set_count: byInsertSet.length,
              rows: byInsertSet,
              match_mode: 'fuzzy_rejected_below_threshold',
            }),
          });
        }
        chosen = top;
        alternateRows = [];
        parallelMatchMode = 'fuzzy_best_no_alternates';
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
      search_set: setLabel,
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
      parallel_debug: buildParallelDebugPayload({
        requested_parallel: parallelName,
        after_number_count: byNumber.length,
        after_insert_set_count: byInsertSet.length,
        rows: byInsertSet,
        match_mode: parallelMatchMode,
      }),
      ...(persistMasterVariantId ? { persisted_master } : {}),
    });
  } catch (e) {
    console.error(JSON.stringify({ tag: LOG_TAG, event: 'exception', message: String(e) }));
    return json({ error: 'Internal server error', details: String(e) }, 500);
  }
});
