/**
 * Scheduled refresh: guide-price data → `current_prices` on `master_card_definitions`.
 *
 * Uses `POST /v1/cards/batch-price-estimate` (≤100 card/grade pairs per HTTP call) when possible,
 * then merges with existing DB rows so uncommon grades are preserved. Falls back to
 * `all-prices-by-card` per master if the batch request fails.
 *
 * Auth: `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>` (pg_cron).
 * Secrets: `CARDHEDGE_API_KEY` or `CARDHEDGER_API_KEY`.
 */
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import {
  CARDHEDGE_CRON_BATCH_GRADES,
  fetchCardHedgeAllLatestPrices,
  fetchCardHedgeBatchPriceEstimateAllChunks,
  type BatchPriceEstimateRow,
} from '../_shared/cardhedge_all_prices.ts';
import { persistGuidePricesOntoMaster } from '../_shared/cardhedge_persist_master.ts';

/** Max distinct stale masters to refresh per invocation. */
const DAILY_LIMIT = 10;
const STALE_MS = 23 * 60 * 60 * 1000;
const DELAY_MS = 400;
/** Rows to load before JS sort/dedupe (many copies can share one master). */
const DAILY_FETCH_CAP = 200;

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function cardHedgeApiKey(): string | null {
  return (
    Deno.env.get('CARDHEDGE_API_KEY')?.trim() ||
    Deno.env.get('CARDHEDGER_API_KEY')?.trim() ||
    null
  );
}

function vaultRank(c: { current_value: number | null; price_paid: number | null }): number {
  const cv = typeof c.current_value === 'number' && Number.isFinite(c.current_value) ? c.current_value : 0;
  const pp = typeof c.price_paid === 'number' && Number.isFinite(c.price_paid) ? c.price_paid : 0;
  return Math.max(cv, pp);
}

function masterStale(cardhedgeFetchedAt: string | null | undefined): boolean {
  if (cardhedgeFetchedAt == null || cardhedgeFetchedAt === '') return true;
  return new Date(cardhedgeFetchedAt).getTime() < Date.now() - STALE_MS;
}

type MasterEmbed = {
  id: string;
  cardhedge_id: string | null;
  cardhedge_fetched_at: string | null;
} | null;

type UserCardRow = {
  id: string;
  master_card_id: string | null;
  current_value: number | null;
  price_paid: number | null;
  master_card_definitions: MasterEmbed;
};

type RefreshJob = { masterVariantId: string; guidePriceCardId: string };

/** Stale masters with a linked guide-price card id, highest vault rank first, at most [DAILY_LIMIT]. */
function buildRefreshQueue(dailyRows: UserCardRow[]): RefreshJob[] {
  const sorted = [...dailyRows].sort((a, b) => vaultRank(b) - vaultRank(a));
  const jobs: RefreshJob[] = [];
  const seenMaster = new Set<string>();

  for (const row of sorted) {
    const m = row.master_card_definitions;
    const ch = typeof m?.cardhedge_id === 'string' ? m.cardhedge_id.trim() : '';
    if (!m?.id || !ch) continue;
    if (!masterStale(m.cardhedge_fetched_at)) continue;
    if (seenMaster.has(m.id)) continue;
    if (jobs.length >= DAILY_LIMIT) break;
    seenMaster.add(m.id);
    jobs.push({ masterVariantId: m.id, guidePriceCardId: ch });
  }

  return jobs;
}

async function loadExistingGradePrices(
  admin: SupabaseClient,
  masterVariantId: string,
): Promise<Map<string, number>> {
  const map = new Map<string, number>();
  const { data, error } = await admin
    .from('current_prices')
    .select('grade, price')
    .eq('master_card_id', masterVariantId);
  if (error) {
    console.error('[auto-refresh] load current_prices', error.message);
    return map;
  }
  for (const row of data ?? []) {
    const r = row as Record<string, unknown>;
    const g = String(r.grade ?? '').trim();
    if (!g) continue;
    const pr = r.price;
    const n =
      typeof pr === 'number' && Number.isFinite(pr)
        ? pr
        : parseFloat(String(pr ?? '').replace(/[^0-9.-]/g, ''));
    if (Number.isFinite(n) && n > 0) map.set(g, n);
  }
  return map;
}

function applyBatchToPriceMap(
  map: Map<string, number>,
  upstreamCardId: string,
  batchRows: BatchPriceEstimateRow[],
): void {
  for (const row of batchRows) {
    if (row.card_id !== upstreamCardId) continue;
    if (row.error) continue;
    if (row.price == null || row.price <= 0) continue;
    const g = row.grade.trim();
    if (!g) continue;
    map.set(g, row.price);
  }
}

async function persistMergedAndTouchUserCards(
  admin: SupabaseClient,
  job: RefreshJob,
  apiKey: string,
  batchRows: BatchPriceEstimateRow[] | null,
): Promise<boolean> {
  const existing = await loadExistingGradePrices(admin, job.masterVariantId);
  if (batchRows != null) {
    applyBatchToPriceMap(existing, job.guidePriceCardId, batchRows);
  } else {
    const rows = await fetchCardHedgeAllLatestPrices(apiKey, job.guidePriceCardId, { timeoutMs: 20_000 });
    if (!rows || rows.length === 0) return false;
    existing.clear();
    for (const r of rows) {
      const price = parseFloat(String(r.price).replace(/[^0-9.-]/g, '')) || 0;
      const g = r.grade.trim();
      if (g && price > 0) existing.set(g, price);
    }
  }

  const prices = [...existing.entries()]
    .map(([grade, price]) => ({ grade, price }))
    .filter((p) => p.grade && p.price > 0);
  if (prices.length === 0) return false;

  await persistGuidePricesOntoMaster(admin, {
    masterVariantId: job.masterVariantId,
    guidePriceCardId: job.guidePriceCardId,
    prices,
  });
  const nowIso = new Date().toISOString();
  await admin.from('user_cards').update({ value_refreshed_at: nowIso }).eq('master_card_id', job.masterVariantId);
  return true;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  if (token !== serviceRoleKey) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  const apiKey = cardHedgeApiKey();
  if (!apiKey) {
    return new Response(
      JSON.stringify({
        error: 'CARDHEDGE_API_KEY not configured',
        hint: 'Set CARDHEDGE_API_KEY on the auto-refresh-cards Edge Function.',
      }),
      { status: 503, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } },
    );
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  const { data: dailyRaw, error: dailyErr } = await admin
    .from('user_cards')
    .select(
      `
      id, master_card_id, current_value, price_paid,
      master_card_definitions ( id, cardhedge_id, cardhedge_fetched_at )
    `,
    )
    .not('master_card_id', 'is', null)
    .order('current_value', { ascending: false, nullsFirst: false })
    .order('price_paid', { ascending: false, nullsFirst: true })
    .limit(DAILY_FETCH_CAP);

  if (dailyErr) {
    console.error('[auto-refresh] query', dailyErr.message);
    return new Response(JSON.stringify({ error: dailyErr.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  const dailyRows = (dailyRaw ?? []) as UserCardRow[];
  const queue = buildRefreshQueue(dailyRows);
  console.log(`[auto-refresh] guide-price masters=${queue.length} (cap ${DAILY_LIMIT})`);

  if (queue.length === 0) {
    return new Response(JSON.stringify({ refreshed: 0, skipped: 'no stale linked masters' }), {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  const items: { card_id: string; grade: string }[] = [];
  for (const j of queue) {
    for (const g of CARDHEDGE_CRON_BATCH_GRADES) {
      items.push({ card_id: j.guidePriceCardId, grade: g });
    }
  }

  const batchRows = await fetchCardHedgeBatchPriceEstimateAllChunks(apiKey, items, {
    timeoutMs: 45_000,
    delayMsBetweenChunks: DELAY_MS,
  });

  let refreshed = 0;
  let errors = 0;
  let usedBatch = batchRows != null;

  if (usedBatch) {
    for (const job of queue) {
      try {
        const ok = await persistMergedAndTouchUserCards(admin, job, apiKey, batchRows);
        if (!ok) {
          console.error(`[auto-refresh] ✗ batch merge empty master=${job.masterVariantId}`);
          errors++;
        } else {
          console.log(`[auto-refresh] ✓ master=${job.masterVariantId} (batch)`);
          refreshed++;
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`[auto-refresh] ✗ master=${job.masterVariantId}: ${msg}`);
        errors++;
      }
    }
  } else {
    console.warn('[auto-refresh] batch-price-estimate failed; using all-prices-by-card per master');
    for (let i = 0; i < queue.length; i++) {
      const job = queue[i];
      try {
        const ok = await persistMergedAndTouchUserCards(admin, job, apiKey, null);
        if (!ok) {
          console.error(`[auto-refresh] ✗ no prices master=${job.masterVariantId} guideCard=${job.guidePriceCardId}`);
          errors++;
        } else {
          console.log(`[auto-refresh] ✓ master=${job.masterVariantId} (all-prices)`);
          refreshed++;
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`[auto-refresh] ✗ master=${job.masterVariantId}: ${msg}`);
        errors++;
      }
      if (i < queue.length - 1) {
        await new Promise((r) => setTimeout(r, DELAY_MS));
      }
    }
  }

  return new Response(
    JSON.stringify({
      refreshed,
      errors,
      masters: queue.length,
      used_batch_price_estimate: usedBatch,
    }),
    { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } },
  );
});
