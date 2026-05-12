import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  buildCardEbayQuery,
  parseAndFilterSoldComps,
  parseGrade,
} from './comps_master_refresh.ts';
import {
  fetchSoldListingsBrightData,
  soldRefreshRowsToSearchShape,
} from './sold_listings_brightdata.ts';
import { verifyUserJwt } from './supabase_user_jwt.ts';

const HISTORY_LIMIT = 50;
const REFRESH_COOLDOWN_HOURS = 24;

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

function filterSearchLots(items: ReturnType<typeof soldRefreshRowsToSearchShape>): any[] {
  return items.filter(item => !/\blot\b/i.test(item.title ?? ''));
}

function normalizeCompGrade(value: unknown): string {
  const grade = typeof value === 'string' ? value.trim() : '';
  return grade.length > 0 ? grade : 'Raw';
}

function averagesFromCompsRows(allCompsData: any[] | null | undefined) {
  const allComps = ((allCompsData as any[]) ?? []).map((c: any) => ({
    ...c,
    grade: normalizeCompGrade(c.grade),
  }));
  const rawComps = allComps.filter((c: any) => c.grade === 'Raw');
  const psa10Comps = allComps.filter((c: any) => c.grade === 'PSA 10');
  const psa9Comps = allComps.filter((c: any) => c.grade === 'PSA 9');

  const rawAvg = rawComps.length > 0 ? rawComps.reduce((s: number, c: any) => s + (c.price ?? 0), 0) / rawComps.length : 0;
  const psa10Avg = psa10Comps.length > 0 ? psa10Comps.reduce((s: number, c: any) => s + (c.price ?? 0), 0) / psa10Comps.length : 0;
  const psa9Avg = psa9Comps.length > 0 ? psa9Comps.reduce((s: number, c: any) => s + (c.price ?? 0), 0) / psa9Comps.length : 0;

  return { rawAvg, psa10Avg, psa9Avg };
}

async function fetchSoldListingsProvider(query: string, path: 'refresh' | 'search'): Promise<any[]> {
  try {
    const rows = await fetchSoldListingsBrightData(query);
    console.log(`[sold-comps/${path}] provider=brightdata rows: ${rows.length}`);
    return rows;
  } catch (e: unknown) {
    const msg = String((e as { message?: string })?.message ?? e ?? '');
    console.error(`[sold-comps/${path}] brightdata failed: ${msg}`);
    if (msg.includes('brightdata_not_configured') || msg.includes('brightdata_async_missing_customer')) {
      throw new Error('provider_not_configured');
    }
    const blocked =
      msg.includes('ebay_bot_protection_page') ||
      msg.includes('brightdata_empty_body') ||
      msg.includes('brightdata_unlock_failed');
    if (blocked) {
      throw new Error('ebay_bot_protection_page');
    }
    throw e;
  }
}

function parallelNameFromMasterEmbed(master: Record<string, unknown>): string {
  const sp = master.set_parallels as Record<string, unknown> | Record<string, unknown>[] | null | undefined;
  if (!sp) return 'Base';
  const row = Array.isArray(sp) ? (sp[0] as Record<string, unknown> | undefined) : (sp as Record<string, unknown>);
  const n = typeof row?.name === 'string' ? row.name.trim() : '';
  return n.length > 0 ? n : 'Base';
}

/**
 * Sold comps via Bright Data Web Unlocker (`sold_listings_brightdata.ts`).
 *
 * Handles both:
 * - refresh path: { masterCardId } — parallel comes from `master_card_definitions.parallel_id` → `set_parallels`
 * - search path: { query }
 */
export async function handleSoldCompsUnified(req: Request): Promise<Response> {
  console.log('[sold-comps] method:', req.method);
  if (req.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Unauthorized' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const userId = await verifyUserJwt(authHeader, supabaseUrl);
    if (!userId) return json({ error: 'Unauthorized' }, 401);

    const body = await req.json() as Record<string, unknown>;
    const masterCardId = body.masterCardId as string | undefined;
    const queryRaw = body.query as string | undefined;

    const doRefresh = typeof masterCardId === 'string' && masterCardId.trim().length > 0;

    if (doRefresh) {
      const admin = createClient(supabaseUrl, serviceRoleKey);

      const { data: masterCard, error: mcError } = await admin
        .from('master_card_definitions')
        .select(`
      id, is_auto, is_patch, serial_max,
      set_parallels!parallel_id ( name ),
      set_cards (
        player, card_number, is_rookie, set_id,
        sets ( id, name, releases ( year, name, sport ) )
      )
    `)
        .eq('id', masterCardId)
        .single();

      if (mcError || !masterCard) {
        return json({ error: 'Master card not found' }, 404);
      }

      const sc = (masterCard as any).set_cards ?? {};
      const setData = sc.sets ?? {};
      const setIdForParallels = setData.id as string | undefined;

      const { data: allParallels } = await admin
        .from('set_parallels')
        .select('name')
        .eq('set_id', setIdForParallels ?? sc.set_id);
      const allParallelNames = (allParallels as any[])?.map((p: any) => p.name) ?? [];

      const mcd = masterCard as any;
      const release = setData.releases ?? {};
      const pn = parallelNameFromMasterEmbed(mcd as Record<string, unknown>);

      const cardRow = {
        year: release.year,
        release_name: release.name,
        set_name: setData.name,
        player: sc.player,
        card_number: sc.card_number,
        parallel_type: pn,
        is_auto: mcd.is_auto,
        is_patch: mcd.is_patch,
        is_rookie: sc.is_rookie,
        serial_max: mcd.serial_max,
        is_graded: false,
        grader: null,
        grade_value: null,
      };

      const query = buildCardEbayQuery(cardRow);
      console.log(`[sold-comps/refresh] query: "${query}", parallel: "${pn}"`);

      // Cooldown: if we fetched this variant recently, return cached rows
      // and avoid another provider call.
      const cooldownCutoffIso = new Date(Date.now() - REFRESH_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString();
      const { data: recentCompsData } = await admin
        .from('card_sold_comps')
        .select('price, grade, title, fetched_at')
        .eq('master_card_id', masterCardId)
        .gte('fetched_at', cooldownCutoffIso)
        .limit(1);

      const recentRowCount = (recentCompsData ?? []).length;
      console.log(
        `[sold-comps/refresh] cooldown_check recent_rows=${recentRowCount} window_h=${REFRESH_COOLDOWN_HOURS}`,
      );

      if (recentRowCount > 0) {
        console.log(`[sold-comps/refresh] cooldown hit for ${masterCardId} ${pn}; skipping Bright Data`);
        const { data: allCompsData } = await admin
          .from('card_sold_comps')
          .select('price, grade')
          .eq('master_card_id', masterCardId);

        const { rawAvg, psa10Avg, psa9Avg } = averagesFromCompsRows(allCompsData as any[]);
        return json({
          comps: [],
          rawAvg,
          psa10Avg,
          psa9Avg,
          totalCount: 0,
          query,
          cached: true,
        });
      }

      // If the last refresh produced zero rows, still honor cooldown to avoid
      // re-hitting provider repeatedly for likely-empty searches.
      const { data: recentRefreshMarker } = await admin
        .from('card_comps_refresh_log')
        .select('last_refreshed_at, last_result_count')
        .eq('master_card_id', masterCardId)
        .gte('last_refreshed_at', cooldownCutoffIso)
        .maybeSingle();

      if (recentRefreshMarker && Number(recentRefreshMarker.last_result_count ?? 0) <= 0) {
        console.log(`[sold-comps/refresh] cooldown hit (zero-result marker) for ${masterCardId} ${pn}`);
        const { data: allCompsData } = await admin
          .from('card_sold_comps')
          .select('price, grade')
          .eq('master_card_id', masterCardId);

        const { rawAvg, psa10Avg, psa9Avg } = averagesFromCompsRows(allCompsData as any[]);
        return json({
          comps: [],
          rawAvg,
          psa10Avg,
          psa9Avg,
          totalCount: 0,
          query,
          cached: true,
          zeroResultCooldown: true,
        });
      }

      let raw: any[];
      try {
        console.log('[sold-comps/refresh] invoking Bright Data (fresh fetch, no cooldown)');
        raw = await fetchSoldListingsProvider(query, 'refresh');
      } catch (e: any) {
        const msg = String(e?.message ?? e ?? '');
        console.error('[sold-comps/refresh] provider error:', msg);
        // Graceful degradation: keep app usable by returning latest stored comps
        // instead of a hard 502 when provider access is blocked.
        const { data: staleCompsData } = await admin
          .from('card_sold_comps')
          .select('price, grade')
          .eq('master_card_id', masterCardId);
        const staleCount = (staleCompsData as any[] | null)?.length ?? 0;
        if (staleCount > 0) {
          const { rawAvg, psa10Avg, psa9Avg } = averagesFromCompsRows(staleCompsData as any[]);
          return json({
            comps: [],
            rawAvg,
            psa10Avg,
            psa9Avg,
            totalCount: staleCount,
            query,
            cached: true,
            stale: true,
            warning: 'Using previously stored comps because marketplace refresh is temporarily blocked.',
          });
        }
        if (msg.includes('provider_not_configured')) {
          return json({
            error:
              'Bright Data: set BRIGHTDATA_API_KEY and BRIGHTDATA_UNLOCKER_ZONE. Optional: BRIGHTDATA_PROXY_USERNAME for async. See supabase/functions/brightdata.env.example.',
          }, 502);
        }
        if (msg.includes('ebay_bot_protection_page')) {
          return json({ error: 'Marketplace temporarily blocked this refresh request. Please try again later.' }, 502);
        }
        return json({ error: 'Failed to fetch sold comps' }, 502);
      }

      const rejectDebug: Array<{ title: string; reason: string }> = [];
      const items = parseAndFilterSoldComps(
        raw,
        query,
        pn,
        allParallelNames,
        sc.card_number ?? undefined,
        setData.name ?? undefined,
        rejectDebug,
      );
      console.log(`[sold-comps/refresh] filtered rows: ${items.length}`);
      if (items.length === 0) {
        const counts = rejectDebug.reduce((acc: Record<string, number>, row) => {
          acc[row.reason] = (acc[row.reason] ?? 0) + 1;
          return acc;
        }, {});
        const topReasons = Object.entries(counts)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 5)
          .map(([reason, count]) => `${reason}:${count}`)
          .join(', ');
        console.warn(
          `[sold-comps/refresh] filter dropped all rows for ${masterCardId}; raw=${raw.length}; reasons=${topReasons}`,
        );
        console.warn(
          `[sold-comps/refresh] sample rejects: ${JSON.stringify(rejectDebug.slice(0, 10))}`,
        );
      }

      await admin.from('card_sold_comps')
        .delete()
        .eq('master_card_id', masterCardId);

      if (items.length > 0) {
        const rows = items.map((item: any) => {
          const grade = parseGrade(item.title);
          return {
            master_card_id: masterCardId,
            parallel_name: pn,
            grade,
            ebay_item_id: item.itemId ?? null,
            title: item.title ?? '',
            price: parseFloat(item.price?.value ?? '0'),
            currency: item.price?.currency ?? 'USD',
            sale_type: typeof item.buyingOptions === 'string' ? item.buyingOptions : 'fixed_price',
            sold_at: item.itemEndDate ?? null,
            url: item.itemWebUrl ?? null,
            image_url: item.imageUrl ?? null,
          };
        });
        await admin.from('card_sold_comps').insert(rows);
      }

      await admin
        .from('card_comps_refresh_log')
        .upsert(
          {
            master_card_id: masterCardId,
            parallel_name: pn,
            last_refreshed_at: new Date().toISOString(),
            last_result_count: items.length,
          },
          { onConflict: 'master_card_id' },
        );

      const { data: allCompsData } = await admin
        .from('card_sold_comps')
        .select('price, grade')
        .eq('master_card_id', masterCardId);

      const { rawAvg, psa10Avg, psa9Avg } = averagesFromCompsRows(allCompsData as any[]);

      return json({
        comps: items,
        rawAvg,
        psa10Avg,
        psa9Avg,
        totalCount: items.length,
        query,
      });
    }

    const queryText = typeof queryRaw === 'string' ? queryRaw.trim() : '';
    if (!queryText) {
      return json({ error: 'Provide { masterCardId } or { query }' }, 400);
    }

    let rawRows: any[];
    try {
      rawRows = await fetchSoldListingsProvider(queryText, 'search');
    } catch (e: any) {
      console.error('[sold-comps/search] provider error:', e?.message ?? e);
      if (String(e?.message ?? e ?? '').includes('provider_not_configured')) {
        return json({
          error:
            'Bright Data: set BRIGHTDATA_API_KEY and BRIGHTDATA_UNLOCKER_ZONE. See supabase/functions/brightdata.env.example.',
        }, 502);
      }
      return json({ error: 'Failed to fetch sold comps' }, 502);
    }

    const items = filterSearchLots(soldRefreshRowsToSearchShape(rawRows));

    const prices = items.map((i: { price: number }) => i.price).filter((p: number) => p > 0);
    const avgPrice = prices.length > 0 ? prices.reduce((s, p) => s + p, 0) / prices.length : null;

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: existing } = await admin
      .from('lookup_history')
      .select('id')
      .eq('user_id', userId)
      .ilike('query', queryText)
      .limit(1)
      .single();

    if (!existing) {
      const { count } = await admin
        .from('lookup_history')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', userId);

      if ((count ?? 0) >= HISTORY_LIMIT) {
        const { data: oldest } = await admin
          .from('lookup_history')
          .select('id')
          .eq('user_id', userId)
          .order('timestamp', { ascending: true })
          .limit(1)
          .single();
        if (oldest) await admin.from('lookup_history').delete().eq('id', oldest.id);
      }

      await admin.from('lookup_history').insert({
        user_id: userId,
        query: queryText,
        results: items,
        timestamp: new Date().toISOString(),
      });
    }

    return json({ items, avgPrice });
  } catch (e: any) {
    console.error('[sold-comps] unhandled:', e?.message ?? e);
    return json({ error: 'Internal server error', detail: e?.message }, 500);
  }
}
