import { createClient } from 'jsr:@supabase/supabase-js@2';
import { CardsightApiError } from '../_shared/cardsight_fetch.ts';
import { segmentToSport } from '../_shared/cardsight_catalog_releases.ts';
import {
  getSegmentSyncMeta,
  indexRowsToSummaries,
  isSegmentCacheFresh,
  loadReleaseIndexBySport,
  syncReleaseIndexFromCardSight,
} from '../_shared/cardsight_release_index.ts';

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

function countImportedSets(setsRaw: { set_cards?: { count?: number }[] }[]): number {
  let imported = 0;
  for (const s of setsRaw) {
    const defs = s.set_cards;
    if (defs != null && defs.length > 0 && (defs[0]?.count ?? 0) > 0) imported++;
  }
  return imported;
}

type ReleaseCoverage = {
  set_count: number;
  sets_with_parallels: number;
  sets_with_cards: number;
  sets_cards_complete: number;
  expected_card_total: number;
  vault_card_total: number;
};

type VaultRow = {
  id: string;
  name: string;
  year: number;
  cardsight_id?: string | null;
  sets?: { set_cards?: { count?: number }[] }[];
};

async function loadCoverageBySport(
  supabase: ReturnType<typeof createClient>,
  sport: string,
): Promise<Map<string, ReleaseCoverage>> {
  const coverageByReleaseId = new Map<string, ReleaseCoverage>();
  try {
    const { data: coverageRows, error: covError } = await supabase
      .from('catalog_release_coverage')
      .select(
        'release_id, set_count, sets_with_parallels, sets_with_cards, sets_cards_complete, expected_card_total, vault_card_total',
      )
      .eq('sport', sport);
    if (covError) throw new Error(covError.message);
    for (const row of coverageRows ?? []) {
      const rid = (row as { release_id: string }).release_id;
      coverageByReleaseId.set(rid, row as ReleaseCoverage);
    }
  } catch (e) {
    console.warn('[catalog-releases-list] coverage view unavailable:', e);
  }
  return coverageByReleaseId;
}

async function loadVaultByCardsightId(
  supabase: ReturnType<typeof createClient>,
  sport: string,
): Promise<Map<string, VaultRow>> {
  const { data: vaultRows, error: vaultError } = await supabase
    .from('releases')
    .select('id, name, year, cardsight_id, sets(id, set_cards(count))')
    .eq('sport', sport);
  if (vaultError) throw new Error(vaultError.message);

  const map = new Map<string, VaultRow>();
  for (const row of (vaultRows ?? []) as VaultRow[]) {
    if (row.cardsight_id) map.set(row.cardsight_id, row);
  }
  return map;
}

function releaseRowFromVault(
  vault: VaultRow,
  cov: ReleaseCoverage | null | undefined,
) {
  const setsRaw = vault.sets ?? [];
  const legacySetCount = setsRaw.length;
  const legacyImported = countImportedSets(setsRaw);
  return {
    cardsightId: vault.cardsight_id ?? `vault:${vault.id}`,
    name: vault.name,
    year: vault.year,
    inVault: true,
    vaultReleaseId: vault.id,
    setCount: cov?.set_count ?? legacySetCount,
    importedSetCount: cov?.sets_with_cards ?? legacyImported,
    setsWithParallels: cov?.sets_with_parallels ?? 0,
    setsCardsComplete: cov?.sets_cards_complete ?? 0,
    vaultCardTotal: Number(cov?.vault_card_total ?? 0),
    expectedCardTotal: Number(cov?.expected_card_total ?? 0),
  };
}

function mergeCatalogWithVault(
  catalog: { id: string; name: string; year: string }[],
  vaultByCardsightId: Map<string, VaultRow>,
  coverageByReleaseId: Map<string, ReleaseCoverage>,
) {
  return catalog.map((r) => {
    const year = parseInt(String(r.year), 10);
    const vault = vaultByCardsightId.get(r.id) ?? null;
    const vaultReleaseId = vault?.id ?? null;
    const setsRaw = vault?.sets ?? [];
    const cov = vaultReleaseId ? coverageByReleaseId.get(vaultReleaseId) : null;
    const legacySetCount = setsRaw.length;
    const legacyImported = vault != null ? countImportedSets(setsRaw) : 0;
    return {
      cardsightId: r.id,
      name: r.name,
      year: Number.isFinite(year) ? year : null,
      inVault: vaultReleaseId != null,
      vaultReleaseId,
      setCount: cov?.set_count ?? legacySetCount,
      importedSetCount: cov?.sets_with_cards ?? legacyImported,
      setsWithParallels: cov?.sets_with_parallels ?? 0,
      setsCardsComplete: cov?.sets_cards_complete ?? 0,
      vaultCardTotal: Number(cov?.vault_card_total ?? 0),
      expectedCardTotal: Number(cov?.expected_card_total ?? 0),
    };
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS, status: 200 });

  const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
  if (!apiKey) return json({ error: 'API key not configured' }, 500);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Missing authorization' }, 401);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: 'Unauthorized' }, 401);

  const { data: profile } = await supabase
    .from('profiles')
    .select('is_app_admin')
    .eq('id', user.id)
    .single();
  if (!profile?.is_app_admin) return json({ error: 'Forbidden' }, 403);

  try {
    const { segment, refresh } = await req.json() as {
      segment: string;
      refresh?: boolean;
    };
    if (!segment) return json({ error: 'segment is required' }, 400);

    const sport = segmentToSport(segment);
    const forceRefresh = refresh === true;

    const [vaultByCardsightId, coverageByReleaseId, syncMeta, cachedIndex] = await Promise.all([
      loadVaultByCardsightId(supabase, sport),
      loadCoverageBySport(supabase, sport),
      getSegmentSyncMeta(supabase, segment),
      loadReleaseIndexBySport(supabase, sport),
    ]);

    const cacheFresh = !forceRefresh && isSegmentCacheFresh(syncMeta) && cachedIndex.length > 0;
    let catalog = cacheFresh ? indexRowsToSummaries(cachedIndex) : [];
    let fromCache = cacheFresh;
    let syncedPages = 0;
    let notice: string | undefined;

    if (!cacheFresh) {
      try {
        const syncResult = await syncReleaseIndexFromCardSight(
          supabase,
          apiKey,
          segment,
          sport,
        );
        syncedPages = syncResult.pages;
        const freshIndex = await loadReleaseIndexBySport(supabase, sport);
        catalog = indexRowsToSummaries(freshIndex);
        fromCache = false;
      } catch (e) {
        if (cachedIndex.length > 0) {
          catalog = indexRowsToSummaries(cachedIndex);
          fromCache = true;
          if (e instanceof CardsightApiError && e.isRateLimited) {
            notice =
              'CardSight rate limit — showing cached release list. Pull to refresh when quota resets.';
          } else {
            notice = 'Could not refresh from CardSight — showing cached release list.';
          }
          console.warn('[catalog-releases-list] sync failed, using cache:', e);
        } else if (e instanceof CardsightApiError && e.isRateLimited) {
          const vaultOnlyRows = Array.from(vaultByCardsightId.values()).map((v) =>
            releaseRowFromVault(v, coverageByReleaseId.get(v.id)),
          );
          return json({
            releases: vaultOnlyRows,
            total: vaultOnlyRows.length,
            inVault: vaultOnlyRows.length,
            missing: 0,
            fromCache: false,
            vaultOnly: true,
            notice:
              'CardSight rate limit reached — showing vault releases only.',
          });
        } else {
          throw e;
        }
      }
    }

    const releases = mergeCatalogWithVault(catalog, vaultByCardsightId, coverageByReleaseId);
    const inVault = releases.filter((r) => r.inVault).length;

    return json({
      releases,
      total: releases.length,
      inVault,
      missing: releases.length - inVault,
      fromCache,
      vaultOnly: false,
      syncedPages,
      cacheSyncedAt: syncMeta?.last_synced_at ?? null,
      notice,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-releases-list]', msg);
    return json({ error: msg }, 500);
  }
});
