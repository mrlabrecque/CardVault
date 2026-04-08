const CARDSIGHT_BASE = 'https://api.cardsight.ai';

function getHeaders(): Record<string, string> {
  return { 'X-API-Key': process.env.CARDSIGHT_API_KEY! };
}

export interface CardsightRelease {
  id: string;
  segmentId: string;
  manufacturerId: string;
  year: string;
  name: string;
  description: string;
  is_identifiable: boolean;
  sets?: CardsightSetSummary[];
}

export interface CardsightSetSummary {
  id: string;
  name: string;
  description: string;
  cardCount: number;
  parallelCount: number;
  is_identifiable: boolean;
}

export interface CardsightSetDetail {
  id: string;
  releaseId: string;
  name: string;
  description: string;
  cardCount: number;
  parallelCount: number;
  is_identifiable: boolean;
  parallels: CardsightParallel[];
}

export interface CardsightParallel {
  id: string;
  name: string;
  description?: string;
  numberedTo?: number;
  isPartial?: boolean;
  setId: string;
}

export interface CardsightSegment {
  id: string;
  name: string;
}

const SEGMENT_TO_SPORT: Record<string, string> = {
  baseball:   'Baseball',
  mlb:        'Baseball',
  basketball: 'Basketball',
  nba:        'Basketball',
  football:   'Football',
  nfl:        'Football',
  soccer:     'Soccer',
  mls:        'Soccer',
};

export function mapSegmentToSport(segmentName: string): string | null {
  return SEGMENT_TO_SPORT[segmentName.toLowerCase()] ?? null;
}

export async function searchReleases(params: {
  year?: number;
  manufacturer?: string;
  segment?: string;
}): Promise<CardsightRelease[]> {
  const url = new URL(`${CARDSIGHT_BASE}/v1/catalog/releases`);
  if (params.year)         url.searchParams.set('year', String(params.year));
  if (params.manufacturer) url.searchParams.set('manufacturer', params.manufacturer);
  if (params.segment)      url.searchParams.set('segment', params.segment);

  const res = await fetch(url.toString(), { headers: getHeaders() });
  if (!res.ok) throw new Error(`CardSight search failed: ${res.status} ${res.statusText}`);
  const data = await res.json() as { releases?: CardsightRelease[] };
  return data.releases ?? [];
}

export async function getReleaseDetails(id: string): Promise<CardsightRelease> {
  const url = `${CARDSIGHT_BASE}/v1/catalog/releases/${id}`;
  const res = await fetch(url, { headers: getHeaders() });
  if (!res.ok) throw new Error(`CardSight release details failed: ${res.status} ${res.statusText}`);
  return res.json() as Promise<CardsightRelease>;
}

export async function getSetDetails(id: string): Promise<CardsightSetDetail> {
  const url = `${CARDSIGHT_BASE}/v1/catalog/sets/${id}`;
  const res = await fetch(url, { headers: getHeaders() });
  if (!res.ok) throw new Error(`CardSight set details failed: ${res.status} ${res.statusText}`);
  return res.json() as Promise<CardsightSetDetail>;
}

export async function getSegment(id: string): Promise<CardsightSegment> {
  const url = `${CARDSIGHT_BASE}/v1/catalog/segments/${id}`;
  const res = await fetch(url, { headers: getHeaders() });
  if (!res.ok) throw new Error(`CardSight segment failed: ${res.status} ${res.statusText}`);
  return res.json() as Promise<CardsightSegment>;
}
