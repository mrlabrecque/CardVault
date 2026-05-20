/**
 * Shared release + set shell upsert from CardSight `GET /v1/catalog/releases/{id}`.
 */

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import type {
  CardSightReleaseDetail,
  CardSightReleaseSetSummary,
} from './cardsight_catalog_releases.ts';

export const SEGMENT_TO_SPORT: Record<string, string> = {
  baseball: 'Baseball', mlb: 'Baseball',
  basketball: 'Basketball', nba: 'Basketball',
  football: 'Football', nfl: 'Football',
  soccer: 'Soccer', mls: 'Soccer',
  hockey: 'Hockey', nhl: 'Hockey',
};

export type VaultSetRow = {
  id: string;
  name: string;
  card_count: number | null;
  cardsight_id: string;
  cardsight_parallel_count: number | null;
};

export async function ensureVaultReleaseForCardSight(
  supabase: SupabaseClient,
  cardsightReleaseId: string,
  releaseData: CardSightReleaseDetail,
  opts: {
    releaseName?: string;
    releaseYear?: string;
    releaseSegmentId?: string;
  } = {},
): Promise<string> {
  const { data: existingRelease } = await supabase
    .from('releases')
    .select('id')
    .eq('cardsight_id', cardsightReleaseId)
    .maybeSingle();

  if (existingRelease) return existingRelease.id as string;

  const name = opts.releaseName ?? releaseData.name;
  const year = opts.releaseYear ?? releaseData.year;
  const segId = opts.releaseSegmentId ?? releaseData.segmentId ?? '';
  const sport = SEGMENT_TO_SPORT[String(segId).toLowerCase()] ?? 'Unknown';
  const slug = [year, name, sport]
    .map((v) => String(v).toLowerCase().trim().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''))
    .filter(Boolean)
    .join('-');

  const { data, error } = await supabase
    .from('releases')
    .insert({
      name,
      year: parseInt(String(year), 10),
      sport,
      release_type: 'Hobby',
      set_slug: slug,
      cardsight_id: cardsightReleaseId,
    })
    .select('id')
    .single();

  if (error && error.code === '23505') {
    const { data: raceWinner } = await supabase
      .from('releases')
      .select('id')
      .eq('cardsight_id', cardsightReleaseId)
      .single();
    return (raceWinner as { id: string }).id;
  }
  if (error) throw new Error(error.message);
  return (data as { id: string }).id;
}

export async function upsertVaultSetsFromCatalog(
  supabase: SupabaseClient,
  releaseId: string,
  catalogSets: CardSightReleaseSetSummary[],
): Promise<VaultSetRow[]> {
  if (catalogSets.length === 0) return [];

  const setMap = new Map<string, {
    release_id: string;
    name: string;
    card_count: number | null;
    cardsight_parallel_count: number | null;
    cardsight_id: string;
  }>();

  for (const s of catalogSets) {
    const key = `${releaseId}|${s.name}`;
    if (!setMap.has(key)) {
      setMap.set(key, {
        release_id: releaseId,
        name: s.name,
        card_count: s.cardCount ?? null,
        cardsight_parallel_count: s.parallelCount ?? null,
        cardsight_id: s.id,
      });
    }
  }

  const { data: dbSets, error: setsError } = await supabase
    .from('sets')
    .upsert(Array.from(setMap.values()), { onConflict: 'release_id,name' })
    .select('id, name, card_count, cardsight_id, cardsight_parallel_count');

  if (setsError) throw new Error(setsError.message);
  return (dbSets ?? []) as VaultSetRow[];
}
