export const CARDSIGHT_CATALOG_BASE = 'https://api.cardsight.ai';

/** CardSight `/v1/catalog/releases` max per page (OpenAPI maximum). */
export const CARDSIGHT_RELEASES_PAGE_SIZE = 100;
export const CARDSIGHT_RELEASES_PAGE_DELAY_MS = 250;
/** Safety cap — 500 pages × 100 = 50k releases. */
export const CARDSIGHT_RELEASES_MAX_PAGES = 500;

export const SEGMENT_TO_SPORT: Record<string, string> = {
  baseball: 'Baseball', mlb: 'Baseball',
  basketball: 'Basketball', nba: 'Basketball',
  football: 'Football', nfl: 'Football',
  soccer: 'Soccer', mls: 'Soccer',
  hockey: 'Hockey', nhl: 'Hockey',
};

export type CardSightReleaseSummary = { id: string; name: string; year: string };

export function segmentToSport(segment: string): string {
  return SEGMENT_TO_SPORT[String(segment).toLowerCase()] ?? 'Unknown';
}

export async function fetchAllCardSightReleases(
  apiKey: string,
  segment: string,
  year?: number,
): Promise<CardSightReleaseSummary[]> {
  const all: CardSightReleaseSummary[] = [];
  let skip = 0;
  let totalCount: number | null = null;

  for (let page = 0; page < CARDSIGHT_RELEASES_MAX_PAGES; page++) {
    const url = new URL(`${CARDSIGHT_CATALOG_BASE}/v1/catalog/releases`);
    if (year != null && Number.isFinite(year) && year > 0) {
      url.searchParams.set('year', String(year));
    }
    url.searchParams.set('segment', segment);
    url.searchParams.set('take', String(CARDSIGHT_RELEASES_PAGE_SIZE));
    url.searchParams.set('skip', String(skip));

    const csRes = await fetch(url.toString(), {
      headers: { 'X-API-Key': apiKey },
    });
    if (!csRes.ok) throw new Error(`CardSight API error: ${csRes.status}`);

    const csData = await csRes.json() as {
      releases?: CardSightReleaseSummary[];
      total_count?: number;
    };
    const batch = csData.releases ?? [];
    if (totalCount === null && typeof csData.total_count === 'number') {
      totalCount = csData.total_count;
    }

    if (batch.length === 0) break;

    all.push(...batch);
    skip += batch.length;

    if (batch.length < CARDSIGHT_RELEASES_PAGE_SIZE) break;
    if (totalCount !== null && skip >= totalCount) break;

    await new Promise((r) => setTimeout(r, CARDSIGHT_RELEASES_PAGE_DELAY_MS));
  }

  return all;
}
