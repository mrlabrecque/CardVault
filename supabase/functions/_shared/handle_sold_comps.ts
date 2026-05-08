import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  buildCardEbayQuery,
  parseAndFilterSoldComps,
  parseGrade,
} from './comps_master_refresh.ts';
import {
  fetchSoldListingsDecodo,
  fetchSoldListingsSelfHosted,
  soldRefreshRowsToSearchShape,
} from './sold_listings_sgai.ts';
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

async function fetchSoldListingsWithFallback(query: string, path: 'refresh' | 'search'): Promise<any[]> {
  try {
    const rows = await fetchSoldListingsSelfHosted(query);
    console.log(`[sold-comps/${path}] provider=self_hosted rows: ${rows.length}`);
    return rows;
  } catch (selfHostedError: any) {
    const selfHostedMsg = String(selfHostedError?.message ?? selfHostedError ?? '');
    console.warn(`[sold-comps/${path}] self-hosted failed: ${selfHostedMsg}`);

    try {
      const rows = await fetchSoldListingsDecodo(query);
      console.log(`[sold-comps/${path}] provider=decodo rows: ${rows.length}`);
      return rows;
    } catch (decodoError: any) {
      const decodoMsg = String(decodoError?.message ?? decodoError ?? '');
      console.error(`[sold-comps/${path}] decodo failed: ${decodoMsg}`);

      if (decodoMsg.includes('decodo_not_configured') && selfHostedMsg.includes('self_hosted_not_configured')) {
        throw new Error('provider_not_configured');
      }
      if (selfHostedMsg.includes('ebay_bot_protection_page') || decodoMsg.includes('ebay_bot_protection_page')) {
        throw new Error('ebay_bot_protection_page');
      }
      throw decodoError;
    }
  }
}

/**
 * Handles both:
 * - refresh path: { masterCardId, parallelName }
 * - search path: { query }
 *
 * Refresh takes precedence when both `masterCardId` and `parallelName` are non-empty.
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
    const parallelName = body.parallelName as string | undefined;
    const queryRaw = body.query as string | undefined;

    const doRefresh = !!(masterCardId && parallelName);

    if (doRefresh) {
      const admin = createClient(supabaseUrl, serviceRoleKey);

      const { data: masterCard, error: mcError } = await admin
        .from('master_card_definitions')
        .select(`
      id, player, card_number, is_rookie, is_auto, is_patch, serial_max,
      sets ( id, name, releases ( year, name, sport ) )
    `)
        .eq('id', masterCardId)
        .single();

      if (mcError || !masterCard) {
        return json({ error: 'Master card not found' }, 404);
      }

      const { data: allParallels } = await admin
        .from('set_parallels')
        .select('name')
        .eq('set_id', (masterCard as any).sets.id);

      const allParallelNames = (allParallels as any[])?.map((p: any) => p.name) ?? [];

      const mcd = masterCard as any;
      const setData = mcd.sets ?? {};
      const release = setData.releases ?? {};

      const cardRow = {
        year: release.year,
        release_name: release.name,
        set_name: setData.name,
        player: mcd.player,
        card_number: mcd.card_number,
        parallel_type: parallelName as string,
        is_auto: mcd.is_auto,
        is_patch: mcd.is_patch,
        is_rookie: mcd.is_rookie,
        serial_max: mcd.serial_max,
        is_graded: false,
        grader: null,
        grade_value: null,
      };

      const query = buildCardEbayQuery(cardRow);
      console.log(`[sold-comps/refresh] query: "${query}", parallel: "${parallelName}"`);

      // Cooldown: if we fetched this master+parallel recently, return cached rows
      // and avoid another provider call.
      const cooldownCutoffIso = new Date(Date.now() - REFRESH_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString();
      const { data: recentCompsData } = await admin
        .from('card_sold_comps')
        .select('price, grade, title, fetched_at')
        .eq('master_card_id', masterCardId)
        .eq('parallel_name', parallelName)
        .gte('fetched_at', cooldownCutoffIso)
        .limit(1);

      if ((recentCompsData ?? []).length > 0) {
        console.log(`[sold-comps/refresh] cooldown hit for ${masterCardId} ${parallelName}; skipping provider call`);
        const { data: allCompsData } = await admin
          .from('card_sold_comps')
          .select('price, grade')
          .eq('master_card_id', masterCardId)
          .eq('parallel_name', parallelName);

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

      let raw: any[];
      try {
        raw = await fetchSoldListingsWithFallback(query, 'refresh');
      } catch (e: any) {
        const msg = String(e?.message ?? e ?? '');
        console.error('[sold-comps/refresh] provider error:', msg);
        // Graceful degradation: keep app usable by returning latest stored comps
        // instead of a hard 502 when provider access is blocked.
        const { data: staleCompsData } = await admin
          .from('card_sold_comps')
          .select('price, grade')
          .eq('master_card_id', masterCardId)
          .eq('parallel_name', parallelName);
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
          return json({ error: 'Scraper provider is not configured.' }, 502);
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
        parallelName as string,
        allParallelNames,
        mcd.card_number ?? undefined,
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
        .eq('master_card_id', masterCardId)
        .eq('parallel_name', parallelName);

      if (items.length > 0) {
        const rows = items.map((item: any) => {
          const grade = parseGrade(item.title);
          return {
            master_card_id: masterCardId,
            parallel_name: parallelName,
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

      const { data: allCompsData } = await admin
        .from('card_sold_comps')
        .select('price, grade')
        .eq('master_card_id', masterCardId)
        .eq('parallel_name', parallelName);

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
      return json({ error: 'Provide { masterCardId, parallelName } or { query }' }, 400);
    }

    let rawRows: any[];
    try {
      rawRows = await fetchSoldListingsWithFallback(queryText, 'search');
    } catch (e: any) {
      console.error('[sold-comps/search] provider error:', e?.message ?? e);
      if (String(e?.message ?? e ?? '').includes('provider_not_configured')) {
        return json({ error: 'Scraper provider is not configured.' }, 502);
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
