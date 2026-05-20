/**
 * Cache CardSight `GET /v1/catalog/releases` pages in `cardsight_release_index`.
 */

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import {
  CARDSIGHT_CATALOG_BASE,
  CARDSIGHT_RELEASES_MAX_PAGES,
  CARDSIGHT_RELEASES_PAGE_DELAY_MS,
  CARDSIGHT_RELEASES_PAGE_SIZE,
  type CardSightReleaseSummary,
} from './cardsight_catalog_releases.ts';
import { cardsightFetch } from './cardsight_fetch.ts';

/** Use cached index when last full sync is newer than this (admin list). */
export const RELEASE_INDEX_CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export type ReleaseIndexRow = {
  cardsight_id: string;
  segment: string;
  sport: string;
  name: string;
  year: number | null;
  synced_at: string;
};

export type SegmentSyncMeta = {
  segment: string;
  sport: string;
  release_count: number;
  last_synced_at: string | null;
  last_sync_error: string | null;
};

function resolveYear(yearStr: string, name: string): number | null {
  const parsed = parseInt(String(yearStr), 10);
  if (Number.isFinite(parsed) && parsed > 1900) return parsed;
  const fromName = name.match(/\b(19|20)\d{2}\b/);
  if (fromName) return parseInt(fromName[0], 10);
  return null;
}

export async function getSegmentSyncMeta(
  supabase: SupabaseClient,
  segment: string,
): Promise<SegmentSyncMeta | null> {
  const { data, error } = await supabase
    .from('cardsight_segment_sync')
    .select('segment, sport, release_count, last_synced_at, last_sync_error')
    .eq('segment', segment)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return (data as SegmentSyncMeta | null) ?? null;
}

export function isSegmentCacheFresh(meta: SegmentSyncMeta | null): boolean {
  if (!meta?.last_synced_at || meta.release_count <= 0) return false;
  const synced = Date.parse(meta.last_synced_at);
  if (Number.isNaN(synced)) return false;
  return Date.now() - synced < RELEASE_INDEX_CACHE_TTL_MS;
}

export async function loadReleaseIndexBySport(
  supabase: SupabaseClient,
  sport: string,
): Promise<ReleaseIndexRow[]> {
  const { data, error } = await supabase
    .from('cardsight_release_index')
    .select('cardsight_id, segment, sport, name, year, synced_at')
    .eq('sport', sport)
    .order('year', { ascending: false, nullsFirst: false })
    .order('name', { ascending: true });
  if (error) throw new Error(error.message);
  return (data ?? []) as ReleaseIndexRow[];
}

export function indexRowsToSummaries(rows: ReleaseIndexRow[]): CardSightReleaseSummary[] {
  return rows.map((r) => ({
    id: r.cardsight_id,
    name: r.name,
    year: r.year != null ? String(r.year) : '',
  }));
}

async function upsertReleaseIndexBatch(
  supabase: SupabaseClient,
  segment: string,
  sport: string,
  batch: CardSightReleaseSummary[],
): Promise<void> {
  if (batch.length === 0) return;
  const now = new Date().toISOString();
  const rows = batch.map((r) => ({
    cardsight_id: r.id,
    segment,
    sport,
    name: r.name,
    year: resolveYear(r.year, r.name),
    synced_at: now,
  }));

  const { error } = await supabase
    .from('cardsight_release_index')
    .upsert(rows, { onConflict: 'cardsight_id' });
  if (error) throw new Error(error.message);
}

/**
 * Paginate CardSight releases for [segment] and upsert each page into the index (+ release shells).
 */
export async function syncReleaseIndexFromCardSight(
  supabase: SupabaseClient,
  apiKey: string,
  segment: string,
  sport: string,
): Promise<{ total: number; pages: number }> {
  let skip = 0;
  let totalCount: number | null = null;
  let total = 0;
  let pages = 0;

  try {
    for (let page = 0; page < CARDSIGHT_RELEASES_MAX_PAGES; page++) {
      const url = new URL(`${CARDSIGHT_CATALOG_BASE}/v1/catalog/releases`);
      url.searchParams.set('segment', segment);
      url.searchParams.set('take', String(CARDSIGHT_RELEASES_PAGE_SIZE));
      url.searchParams.set('skip', String(skip));

      const csRes = await cardsightFetch(url, apiKey);
      const csData = await csRes.json() as {
        releases?: CardSightReleaseSummary[];
        total_count?: number;
      };
      const batch = csData.releases ?? [];
      if (totalCount === null && typeof csData.total_count === 'number') {
        totalCount = csData.total_count;
      }

      if (batch.length === 0) break;

      await upsertReleaseIndexBatch(supabase, segment, sport, batch);
      total += batch.length;
      pages++;
      skip += batch.length;

      if (batch.length < CARDSIGHT_RELEASES_PAGE_SIZE) break;
      if (totalCount !== null && skip >= totalCount) break;

      await new Promise((r) => setTimeout(r, CARDSIGHT_RELEASES_PAGE_DELAY_MS));
    }

    await supabase.from('cardsight_segment_sync').upsert({
      segment,
      sport,
      release_count: total,
      last_synced_at: new Date().toISOString(),
      last_sync_error: null,
    }, { onConflict: 'segment' });

    return { total, pages };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await supabase.from('cardsight_segment_sync').upsert({
      segment,
      sport,
      release_count: total,
      last_sync_error: msg,
    }, { onConflict: 'segment' });
    throw e;
  }
}
