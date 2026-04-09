import { Injectable } from '@angular/core';
import { AuthService } from './auth';
import { environment } from '../../../environments/environment';

export interface CardsightReleaseResult {
  id: string;
  name: string;
  year: string;
  segmentId: string;
  manufacturerId: string;
  is_identifiable: boolean;
}

export interface CardsightImportResult {
  releaseId: string;
  releaseName: string;
  setsCount: number;
  parallelsCount: number;
}

@Injectable({ providedIn: 'root' })
export class CardsightService {
  constructor(private auth: AuthService) {}

  private async authHeaders(): Promise<Record<string, string>> {
    const session = await this.auth.getSession();
    return { Authorization: `Bearer ${session?.access_token ?? ''}` };
  }

  async searchReleases(params: {
    year?: number;
    manufacturer?: string;
    segment?: string;
  }): Promise<CardsightReleaseResult[]> {
    const headers = await this.authHeaders();
    const query = new URLSearchParams();
    if (params.year)         query.set('year',         String(params.year));
    if (params.manufacturer) query.set('manufacturer', params.manufacturer);
    if (params.segment)      query.set('segment',      params.segment);

    const res = await fetch(
      `${environment.apiUrl}/api/cardsight/search?${query}`,
      { headers }
    );
    if (!res.ok) {
      const body = await res.json().catch(() => ({})) as any;
      throw new Error(body?.error ?? `CardSight search failed (${res.status})`);
    }
    const data = await res.json() as CardsightReleaseResult[];
    console.log('[cardsight] search response:', data);
    return data;
  }

  async importRelease(
    cardsightReleaseId: string,
    sport: string | null,
    releaseType: string,
    ebaySearchTemplate: string,
  ): Promise<CardsightImportResult> {
    const headers = await this.authHeaders();
    const res = await fetch(`${environment.apiUrl}/api/cardsight/import`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({ cardsightReleaseId, sport, releaseType, ebaySearchTemplate }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(body.error ?? 'Import failed');
    }
    return res.json();
  }
}
