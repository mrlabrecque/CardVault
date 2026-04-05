import { Injectable, inject, signal } from '@angular/core';
import { AuthService } from './auth';
import { environment } from '../../../environments/environment.development';

export interface Card {
  id: string;
  masterCardId: string;
  player: string;
  cardNumber: string | null;
  sport: string;
  set: string;
  year: number;
  parallel: string;
  grade: string;       // display label: "PSA 10" | "BGS 9.5" | "Raw"
  isGraded: boolean;
  grader: string | null;
  gradeValue: string | null;
  serialNumber: string | null;
  pricePaid: number;
  currentValue: number;
  rookie: boolean;
  autograph: boolean;
  memorabilia: boolean;
}

export interface MasterCard {
  id: string;
  player: string;
  card_number: string | null;
  parallel_type: string | null;
  is_rookie: boolean;
  is_auto: boolean;
  is_patch: boolean;
  is_ssp: boolean;
  serial_max: number | null;
  set_id: string | null;
}

export interface SoldComp {
  id: string;
  user_card_id: string;
  ebay_item_id: string | null;
  title: string;
  price: number;
  currency: string;
  /** 'auction' | 'fixed_price' | 'best_offer'
   *  Note: best_offer price is the listing ask, NOT the accepted offer amount. */
  sale_type: 'auction' | 'fixed_price' | 'best_offer';
  sold_at: string | null;
  url: string | null;
  fetched_at: string;
}

export interface AddCardFormData {
  setId: string;
  masterCardId: string | null; // null = create new master card
  // New master card fields (used when masterCardId is null)
  player: string;
  cardNumber: string;
  parallelType: string;
  isRookie: boolean;
  isAuto: boolean;
  isPatch: boolean;
  isSSP: boolean;
  serialMax: number | null;
  // User instance fields
  pricePaid: number | null;
  serialNumber: string;
  isGraded: boolean;
  grader: string;
  gradeValue: string;
}

@Injectable({ providedIn: 'root' })
export class CardsService {
  private auth = inject(AuthService);
  private get supabase() { return this.auth.getClient(); }

  cards = signal<Card[]>([]);
  readonly valuingCardIds = signal<Set<string>>(new Set());

  getById(id: string): Card | undefined {
    return this.cards().find(c => c.id === id);
  }

  async loadUserCards() {
    const { data, error } = await this.supabase
      .from('user_cards')
      .select(`
        id,
        master_card_id,
        price_paid,
        serial_number,
        current_value,
        is_graded,
        grader,
        grade_value,
        master_card_definitions (
          player,
          card_number,
          parallel_type,
          is_rookie,
          is_auto,
          is_patch,
          sets (
            name,
            year,
            sport
          )
        )
      `)
      .order('created_at', { ascending: false });

    if (error || !data) {
      console.error('[CardsService] loadUserCards error:', error);
      return;
    }

    const cards: Card[] = (data as any[]).map(uc => {
      const master = uc.master_card_definitions ?? {};
      const set = master.sets ?? {};
      const gradeLabel = uc.is_graded
        ? `${uc.grader ?? ''} ${uc.grade_value ?? ''}`.trim()
        : 'Raw';
      return {
        id: uc.id,
        masterCardId: uc.master_card_id,
        player: master.player ?? '',
        cardNumber: master.card_number ?? null,
        sport: set.sport ?? '',
        set: set.name ?? '',
        year: set.year ?? 0,
        parallel: master.parallel_type ?? 'Base',
        grade: gradeLabel,
        isGraded: uc.is_graded ?? false,
        grader: uc.grader ?? null,
        gradeValue: uc.grade_value ?? null,
        serialNumber: uc.serial_number ?? null,
        pricePaid: uc.price_paid ?? 0,
        currentValue: uc.current_value ?? 0,
        rookie: master.is_rookie ?? false,
        autograph: master.is_auto ?? false,
        memorabilia: master.is_patch ?? false,
      };
    });

    this.cards.set(cards);
  }

  async searchMasterCards(setId: string, query: string): Promise<MasterCard[]> {
    if (!query.trim()) return [];
    const { data } = await this.supabase
      .from('master_card_definitions')
      .select('id, player, card_number, parallel_type, is_rookie, is_auto, is_patch, is_ssp, serial_max, set_id')
      .eq('set_id', setId)
      .or(`player.ilike.%${query}%,card_number.ilike.%${query}%`)
      .limit(20);
    return (data as MasterCard[]) ?? [];
  }

  async addCardWithLookup(formData: AddCardFormData): Promise<{ error: any; cardId: string | null }> {
    const userId = this.auth.user()?.id;
    if (!userId) return { error: new Error('Not authenticated'), cardId: null };

    let masterCardId = formData.masterCardId;

    if (!masterCardId) {
      const { data: newMaster, error: masterError } = await this.supabase
        .from('master_card_definitions')
        .insert({
          set_id: formData.setId,
          player: formData.player,
          card_number: formData.cardNumber || null,
          parallel_type: formData.parallelType || 'Base',
          is_rookie: formData.isRookie,
          is_auto: formData.isAuto,
          is_patch: formData.isPatch,
          is_ssp: formData.isSSP,
          serial_max: formData.serialMax,
        })
        .select('id')
        .single();

      if (masterError) return { error: masterError, cardId: null };
      masterCardId = newMaster.id;
    }

    const { data, error } = await this.supabase
      .from('user_cards')
      .insert({
        master_card_id: masterCardId,
        user_id: userId,
        price_paid: formData.pricePaid,
        serial_number: formData.serialNumber || null,
        is_graded: formData.isGraded,
        grader: formData.isGraded ? formData.grader : null,
        grade_value: formData.isGraded ? formData.gradeValue : null,
      })
      .select('id')
      .single();

    if (!error) await this.loadUserCards();
    return { error, cardId: data?.id ?? null };
  }

  async fetchCardComps(cardId: string): Promise<SoldComp[]> {
    const session = await this.auth.getSession();
    if (!session) return [];
    try {
      const res = await fetch(`${environment.apiUrl}/api/comps/card-comps/${cardId}`, {
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      if (!res.ok) return [];
      return res.json();
    } catch {
      return [];
    }
  }

  async deleteCard(cardId: string): Promise<{ error: any }> {
    const { error } = await this.supabase
      .from('user_cards')
      .delete()
      .eq('id', cardId);
    if (!error) {
      this.cards.update(cards => cards.filter(c => c.id !== cardId));
    }
    return { error };
  }

  async fetchMarketValue(cardId: string): Promise<void> {
    this.valuingCardIds.update(ids => { const n = new Set(ids); n.add(cardId); return n; });
    try {
      const session = await this.auth.getSession();
      if (!session) return;

      await fetch(`${environment.apiUrl}/api/comps/card-value`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${session.access_token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ cardId }),
      });

      await this.loadUserCards();
    } catch (e) {
      console.error('[CardsService] fetchMarketValue error:', e);
    } finally {
      this.valuingCardIds.update(ids => { const n = new Set(ids); n.delete(cardId); return n; });
    }
  }
}
