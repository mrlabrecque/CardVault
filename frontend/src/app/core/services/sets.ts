import { Injectable } from '@angular/core';
import { AuthService } from './auth';

export interface SetRecord {
  id: string;
  name: string;
  year: number;
  sport: string;
  release_type: string;
  ebay_search_template: string | null;
  set_slug: string;
  created_at: string;
}

export type CreateSetPayload = Omit<SetRecord, 'id' | 'created_at'>;

@Injectable({ providedIn: 'root' })
export class SetsService {
  constructor(private auth: AuthService) {}

  private get db() {
    return this.auth.getClient().from('sets');
  }

  async getSets(): Promise<SetRecord[]> {
    const { data } = await this.db
      .select('*')
      .order('year', { ascending: false })
      .order('name');
    return (data as SetRecord[]) ?? [];
  }

  async checkDuplicate(name: string, year: number, sport: string): Promise<boolean> {
    const { data } = await this.db
      .select('id')
      .ilike('name', name)
      .eq('year', year)
      .eq('sport', sport)
      .limit(1);
    return (data?.length ?? 0) > 0;
  }

  async createSet(payload: CreateSetPayload) {
    return this.db.insert(payload).select().single();
  }
}
