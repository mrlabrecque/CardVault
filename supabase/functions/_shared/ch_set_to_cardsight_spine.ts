/**
 * Map CardHedge image-search `set` labels → CardSight catalog `releaseId` + `setId`
 * for lazy import. Used by `identify-card` when enriching candidates.
 */
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

const CARDSIGHT_BASE = 'https://api.cardsight.ai';

const SEGMENT_TO_SPORT: Record<string, string> = {
  baseball: 'Baseball',
  mlb: 'Baseball',
  basketball: 'Basketball',
  nba: 'Basketball',
  football: 'Football',
  nfl: 'Football',
  soccer: 'Soccer',
  mls: 'Soccer',
  hockey: 'Hockey',
  nhl: 'Hockey',
};

export type ChCandidateJson = Record<string, unknown>;

export type EnrichSpineContext = {
  supabase: SupabaseClient;
  cardsightApiKey: string;
  cardHedgeApiKey: string;
  sportSlug: string;
};

type SpineMatch = {
  cardsightReleaseId: string | null;
  cardsightSetId: string | null;
  confidence: number;
  source: 'vault_cardsight_ids' | 'cardsight_api' | 'none';
};

function norm(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function scoreStrings(label: string, candidate: string): number {
  const L = norm(label);
  const C = norm(candidate);
  if (!L || !C) return 0;
  if (L === C) return 1;
  if (L.includes(C) || C.includes(L)) return 0.9;
  const wordsL = L.split(/\s+/).filter((w) => w.length > 2);
  const wordsC = new Set(C.split(/\s+/).filter((w) => w.length > 2));
  if (wordsL.length === 0 || wordsC.size === 0) return 0;
  let hits = 0;
  for (const w of wordsL) {
    if (wordsC.has(w)) hits++;
  }
  return hits / Math.max(wordsL.length, wordsC.size);
}

function extractYearsFromLabel(label: string): number[] {
  const out = new Set<number>();
  const re = /\b(19|20)\d{2}\b/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(label)) !== null) {
    const y = parseInt(m[0]!, 10);
    if (Number.isFinite(y)) out.add(y);
  }
  const range = label.match(/\b((?:19|20)\d{2})\s*[-–]\s*((?:19|20)\d{2})\b/);
  if (range) {
    const a = parseInt(range[1]!, 10);
    const b = parseInt(range[2]!, 10);
    if (Number.isFinite(a) && Number.isFinite(b)) {
      const lo = Math.min(a, b);
      const hi = Math.max(a, b);
      for (let y = lo; y <= hi; y++) out.add(y);
    }
  }
  return [...out];
}

function manufacturerGuess(setLabel: string): string {
  let s = setLabel.replace(/\b(19|20)\d{2}\b/g, ' ').replace(/\s+/g, ' ').trim();
  if (s.length > 64) s = s.slice(0, 64);
  return s;
}

function escapeIlike(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

/** CardSight `segment` query param (see catalog-bulk-import). */
function cardsightSegmentForSlug(sportSlug: string): string | null {
  const s = sportSlug.toLowerCase();
  if (s === 'baseball' || s === 'mlb') return 'mlb';
  if (s === 'football' || s === 'nfl') return 'nfl';
  if (s === 'hockey' || s === 'nhl') return 'nhl';
  if (s === 'soccer' || s === 'mls') return 'mls';
  if (s === 'basketball' || s === 'nba') return 'nba';
  return null;
}

/** CardSight catalog list: basketball → `nba` vs `wnba` segment so leagues do not mix. */
function catalogSegmentForCardsightList(
  sportSlug: string,
  sportDisplay: string,
  setLabel: string,
  category: string | null,
): string | null {
  if (sportDisplay === 'Basketball') {
    return inferBasketballLeague(setLabel, category) === 'wnba' ? 'wnba' : 'nba';
  }
  return cardsightSegmentForSlug(sportSlug);
}

/** Infer WNBA vs NBA from CardHedge copy so "Basketball" picker does not land on WNBA Prizm. */
function inferBasketballLeague(setLabel: string, category: string | null): 'nba' | 'wnba' | 'unknown' {
  const blob = `${setLabel} ${category ?? ''}`.toLowerCase();
  if (/\bwnba\b/.test(blob) || blob.includes('wnba')) return 'wnba';
  if (/\bnba\b/.test(blob)) return 'nba';
  if (/\bwomen'?s\b/.test(blob) && /\bbasketball\b/.test(blob)) return 'wnba';
  // CH often omits "NBA" on men's Prizm / Donruss lines; treat as NBA unless WNBA signals above matched.
  if (
    /\b(prizm|optic|mosaic|select|chronicles|hoops|donruss|contenders|revolution|court\s*kings)\b/.test(
      blob,
    )
  ) {
    return 'nba';
  }
  return 'unknown';
}

/** Strong penalty when league implied by CH text disagrees with release/set names. */
function basketballLeagueScoreMultiplier(
  sportDisplay: string,
  setLabel: string,
  category: string | null,
  candidateBlob: string,
): number {
  if (sportDisplay !== 'Basketball') return 1;
  const league = inferBasketballLeague(setLabel, category);
  const c = candidateBlob.toLowerCase();
  const candWnba = /\bwnba\b/.test(c) || c.includes('wnba');
  const candNbaMen = /\bnba\b/.test(c) && !candWnba;
  if (league === 'wnba') {
    if (candNbaMen && !candWnba) return 0.18;
    return 1;
  }
  if (league === 'nba') {
    if (candWnba) return 0.06;
    return 1.08;
  }
  // User chose Basketball but CH text does not say NBA/WNBA — default men’s NBA catalogue, penalize WNBA products.
  if (candWnba) return 0.08;
  return 1;
}

async function tryVaultSpine(
  supabase: SupabaseClient,
  sportDisplay: string,
  setLabel: string,
  category: string | null,
): Promise<SpineMatch | null> {
  if (!setLabel.trim() || !sportDisplay) return null;
  const token = manufacturerGuess(setLabel).split(/\s+/).find((w) => w.length >= 4);
  if (!token) return null;
  const pat = `%${escapeIlike(token)}%`;
  let relQuery = supabase
    .from('releases')
    .select('id, name, year, sport, cardsight_id')
    .eq('sport', sportDisplay)
    .ilike('name', pat)
    .limit(25);
  const bbLeague = inferBasketballLeague(setLabel, category);
  if (sportDisplay === 'Basketball' && bbLeague !== 'wnba') {
    relQuery = relQuery.not('name', 'ilike', '%WNBA%');
  }
  const { data: releases, error: relErr } = await relQuery;
  if (relErr || !releases?.length) return null;

  let best: {
    rel: (typeof releases)[0];
    set: { id: string; name: string; cardsight_id: string | null };
    score: number;
  } | null = null;

  for (const rel of releases) {
    const rid = rel.id as string;
    let setQuery = supabase
      .from('sets')
      .select('id, name, cardsight_id')
      .eq('release_id', rid)
      .limit(80);
    if (sportDisplay === 'Basketball' && bbLeague !== 'wnba') {
      setQuery = setQuery.not('name', 'ilike', '%WNBA%');
    }
    const { data: sets, error: setErr } = await setQuery;
    if (setErr || !sets?.length) continue;
    for (const st of sets) {
      const relName = String(rel.name ?? '');
      const setName = String(st.name ?? '');
      const blob = `${relName} ${setName}`;
      let sc = scoreStrings(setLabel, blob) *
        basketballLeagueScoreMultiplier(sportDisplay, setLabel, category, blob);
      if (sc > 1) sc = 1;
      if (!best || sc > best.score) {
        best = { rel, set: st as { id: string; name: string; cardsight_id: string | null }, score: sc };
      }
    }
  }

  if (!best || best.score < 0.28) return null;
  const relCs = (best.rel.cardsight_id as string | null)?.trim();
  const setCs = (best.set.cardsight_id as string | null)?.trim();
  if (!relCs || !setCs) return null;
  return {
    cardsightReleaseId: relCs,
    cardsightSetId: setCs,
    confidence: Math.min(1, best.score * 1.05),
    source: 'vault_cardsight_ids',
  };
}

async function fetchCardSightReleaseList(
  apiKey: string,
  manufacturer: string,
  year: number,
  segment: string | null,
): Promise<Array<{ id: string; name: string; year?: string | number }>> {
  const url = new URL(`${CARDSIGHT_BASE}/v1/catalog/releases`);
  if (manufacturer.trim()) url.searchParams.set('manufacturer', manufacturer.trim());
  url.searchParams.set('year', String(year));
  const seg = segment?.trim();
  if (seg) url.searchParams.set('segment', seg);
  url.searchParams.set('take', '40');
  const res = await fetch(url.toString(), { headers: { 'X-Api-Key': apiKey } });
  if (!res.ok) return [];
  const data = await res.json() as { releases?: Array<{ id: string; name: string; year?: string | number }> };
  return data.releases ?? [];
}

/** Extra guard when CardSight `segment=nba` still returns a WNBA-titled row. */
function isLikelyWnbaReleaseOrSetName(name: string): boolean {
  const n = name.toLowerCase();
  if (/\bwnba\b/.test(n) || n.includes('wnba')) return true;
  if (/\bwomen'?s\s+national\b/.test(n)) return true;
  return false;
}

async function fetchCardSightSetsForRelease(
  apiKey: string,
  releaseId: string,
): Promise<Array<{ id: string; name: string }>> {
  const res = await fetch(`${CARDSIGHT_BASE}/v1/catalog/releases/${releaseId}`, {
    headers: { 'X-Api-Key': apiKey },
  });
  if (!res.ok) return [];
  const data = await res.json() as { sets?: Array<{ id: string; name: string }> };
  return data.sets ?? [];
}

async function tryCardSightApiSpine(
  apiKey: string,
  sportSlug: string,
  sportDisplay: string,
  setLabel: string,
  category: string | null,
): Promise<SpineMatch | null> {
  if (!setLabel.trim()) return null;
  const mfg = manufacturerGuess(setLabel);
  const years = extractYearsFromLabel(setLabel);
  const isBb = sportSlug.toLowerCase() === 'basketball' || sportDisplay === 'Basketball';
  const listSegment = catalogSegmentForCardsightList(sportSlug, sportDisplay, setLabel, category);
  const yearCandidates = new Set<number>();
  for (const y of years) {
    yearCandidates.add(y);
    if (isBb) {
      yearCandidates.add(y - 1);
      yearCandidates.add(y + 1);
    }
  }
  if (yearCandidates.size === 0) {
    const y = new Date().getFullYear();
    yearCandidates.add(y);
    if (isBb) {
      yearCandidates.add(y - 1);
    }
  }

  let best: { releaseId: string; setId: string; score: number } | null = null;

  for (const year of yearCandidates) {
    const releasesRaw = await fetchCardSightReleaseList(apiKey, mfg, year, listSegment);
    const releases = listSegment === 'nba'
      ? releasesRaw.filter((r) => !isLikelyWnbaReleaseOrSetName(String(r.name ?? '')))
      : releasesRaw;
    const scoredReleases = releases
      .map((r) => {
        const relBlob = `${r.name} ${r.year ?? ''}`;
        let s = scoreStrings(setLabel, relBlob) *
          basketballLeagueScoreMultiplier(sportDisplay, setLabel, category, relBlob);
        if (s > 1) s = 1;
        return { r, s };
      })
      .filter((x) => x.s >= 0.22)
      .sort((a, b) => b.s - a.s)
      .slice(0, 8);

    for (const { r, s: rs } of scoredReleases) {
      const setsRaw = await fetchCardSightSetsForRelease(apiKey, r.id);
      const sets = listSegment === 'nba'
        ? setsRaw.filter((st) => !isLikelyWnbaReleaseOrSetName(String(st.name ?? '')))
        : setsRaw;
      for (const st of sets) {
        const blob = `${r.name} ${st.name}`;
        let ss = scoreStrings(setLabel, blob) * 0.55 + rs * 0.45;
        ss *= basketballLeagueScoreMultiplier(sportDisplay, setLabel, category, blob);
        if (ss > 1) ss = 1;
        if (!best || ss > best.score) {
          best = { releaseId: r.id, setId: st.id, score: ss };
        }
      }
    }
  }

  if (!best || best.score < 0.25) {
    return { cardsightReleaseId: null, cardsightSetId: null, confidence: 0, source: 'none' };
  }
  return {
    cardsightReleaseId: best.releaseId,
    cardsightSetId: best.setId,
    confidence: Math.min(1, best.score),
    source: 'cardsight_api',
  };
}

async function resolveSpineForSetLabel(
  supabase: SupabaseClient,
  cardsightApiKey: string,
  sportSlug: string,
  setLabel: string,
  category: string | null,
  cache: Map<string, SpineMatch>,
): Promise<SpineMatch> {
  const key = `${sportSlug}|${norm(setLabel)}|${norm(category ?? '')}`;
  const hit = cache.get(key);
  if (hit) return hit;

  const sportDisplay = SEGMENT_TO_SPORT[sportSlug.toLowerCase()] ?? '';
  let out: SpineMatch = { cardsightReleaseId: null, cardsightSetId: null, confidence: 0, source: 'none' };

  const v = await tryVaultSpine(supabase, sportDisplay, setLabel, category);
  if (v) out = v;
  else {
    const a = await tryCardSightApiSpine(cardsightApiKey, sportSlug, sportDisplay, setLabel, category);
    if (a.cardsightReleaseId && a.cardsightSetId) out = a;
  }

  cache.set(key, out);
  return out;
}

export async function enrichChCandidatesWithSpine(
  ctx: EnrichSpineContext,
  candidates: ChCandidateJson[],
): Promise<void> {
  const cache = new Map<string, SpineMatch>();
  for (const row of candidates) {
    const setLabel = String(row.set ?? '');
    const cat = typeof row.category === 'string' ? row.category : null;
    const spine = await resolveSpineForSetLabel(
      ctx.supabase,
      ctx.cardsightApiKey,
      ctx.sportSlug,
      setLabel,
      cat,
      cache,
    );
    if (spine.cardsightReleaseId) row.cardsightReleaseId = spine.cardsightReleaseId;
    if (spine.cardsightSetId) row.cardsightSetId = spine.cardsightSetId;
    row.spineMatchConfidence = spine.confidence;
    row.spineMatchSource = spine.source;
  }
}
