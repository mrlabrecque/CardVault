import { Injectable, inject, signal } from '@angular/core';
import { AuthService } from './auth';
import { environment } from '../../../environments/environment';

export interface Card {
  id: string;
  masterCardId: string;
  player: string;
  cardNumber: string | null;
  sport: string;
  set: string;
  year: number;
  checklist: string | null;  // insert name (e.g. "Fireworks") — null for Base Set
  setId: string | null;      // FK → sets.id
  setCardCount: number | null; // sets.card_count — total cards in the set
  parallel: string;          // display name: comes from set_parallels.name or 'Base'
  grade: string;             // display label: "PSA 10" | "BGS 9.5" | "Raw"
  isGraded: boolean;
  grader: string | null;
  gradeValue: string | null;
  serialNumber: string | null;
  serialMax: number | null;
  pricePaid: number;
  currentValue: number;
  rookie: boolean;
  autograph: boolean;
  memorabilia: boolean;
  imageUrl: string | null;
  createdAt: string;
}

export interface MasterCard {
  id: string;
  player: string;
  card_number: string | null;
  set_id: string | null;
  is_rookie: boolean;
  is_auto: boolean;
  is_patch: boolean;
  is_ssp: boolean;
  serial_max: number | null;
  image_url: string | null;
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
  setId: string | null;  // FK → sets.id; null for cards not yet linked to a set
  masterCardId: string | null;   // null = create new master card
  // New master card fields (used when masterCardId is null)
  player: string;
  cardNumber: string;
  serialMax: number | null;
  isRookie: boolean;
  isAuto: boolean;
  isPatch: boolean;
  isSSP: boolean;
  // Parallel (instance-level)
  parallelId: string | null;       // FK to set_parallels; null = Base
  parallelName: string;            // display name (e.g. "Blue Prizm"); always populated
  pendingParallelName: string;     // non-empty when "Other..." is chosen
  // User instance fields
  pricePaid: number | null;
  serialNumber: string;
  isGraded: boolean;
  grader: string;
  gradeValue: string;
}

/** Minimal shape needed to commit a scanned card batch. */
export interface StagedCardPayload {
  masterCardId: string;
  parallelId: string | null;
}

/** Richer staged card for the manual bulk-add flow. */
export interface BulkStagedCard {
  tempId: string;
  masterCardId: string | null;  // null = will be created on commit
  player: string;
  cardNumber: string | null;
  setId: string | null;
  checklistName: string | null;
  parallelId: string | null;
  parallelName: string;
  pricePaid: number;
  serialNumber: string;
  serialMax: number | null;
  isRookie: boolean;
  isAuto: boolean;
  isPatch: boolean;
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
        parallel_id,
        parallel_name,
        price_paid,
        serial_number,
        current_value,
        is_graded,
        grader,
        grade_value,
        created_at,
        master_card_definitions (
          player,
          card_number,
          serial_max,
          is_rookie,
          is_auto,
          is_patch,
          image_url,
          sets (
            id,
            name,
            prefix,
            card_count,
            releases (
              name,
              year,
              sport
            )
          )
        ),
        set_parallels!parallel_id (
          name,
          serial_max
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
      const release = set.releases ?? {};
      const parallelName = uc.set_parallels
        ? uc.set_parallels.name + (uc.set_parallels.serial_max ? ` /${uc.set_parallels.serial_max}` : '')
        : (uc.parallel_name ?? 'Base');
      const gradeLabel = uc.is_graded
        ? `${uc.grader ?? ''} ${uc.grade_value ?? ''}`.trim()
        : 'Raw';
      return {
        id: uc.id,
        masterCardId: uc.master_card_id,
        player: master.player ?? '',
        cardNumber: master.card_number ?? null,
        sport: release.sport ?? '',
        set: release.name ?? '',
        year: release.year ?? 0,
        checklist: set.name ?? null,
        setId: set.id ?? null,
        setCardCount: set.card_count ?? null,
        parallel: parallelName,
        grade: gradeLabel,
        isGraded: uc.is_graded ?? false,
        grader: uc.grader ?? null,
        gradeValue: uc.grade_value ?? null,
        serialNumber: uc.serial_number ?? null,
        serialMax: uc.set_parallels?.serial_max ?? master.serial_max ?? null,
        pricePaid: uc.price_paid ?? 0,
        currentValue: uc.current_value ?? 0,
        rookie: master.is_rookie ?? false,
        autograph: master.is_auto ?? false,
        memorabilia: master.is_patch ?? false,
        imageUrl: master.image_url ?? null,
        createdAt: uc.created_at ?? '',
      };
    });

    this.cards.set(cards);
  }

  async searchMasterCards(setId: string | null, query: string): Promise<MasterCard[]> {
    if (!query.trim()) return [];
    let q = this.supabase
      .from('master_card_definitions')
      .select('id, player, card_number, set_id, is_rookie, is_auto, is_patch, is_ssp, serial_max, image_url')
      .or(`player.ilike.%${query}%,card_number.ilike.%${query}%`)
      .limit(20);
    if (setId) q = q.eq('set_id', setId);
    const { data } = await q;
    return (data as MasterCard[]) ?? [];
  }

  /** Lazily fetch and cache a card image. Fire-and-forget from the call site. */
  async fetchCardImage(masterCardId: string): Promise<string | null> {
    const session = await this.auth.getSession();
    if (!session) return null;
    try {
      const res = await fetch(`${environment.apiUrl}/api/cardsight/cards/${masterCardId}/image`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      if (!res.ok) return null;
      const { image_url } = await res.json();
      return image_url ?? null;
    } catch {
      return null;
    }
  }

  /** Load all master cards for a set into memory (used by scanner Fuse index). */
  async getMasterCardsForSet(setId: string): Promise<MasterCard[]> {
    const { data } = await this.supabase
      .from('master_card_definitions')
      .select('id, player, card_number, set_id, is_rookie, is_auto, is_patch, is_ssp, serial_max')
      .eq('set_id', setId);
    return (data as MasterCard[]) ?? [];
  }

  async addCardWithLookup(formData: AddCardFormData): Promise<{ error: any; cardId: string | null; masterCardId: string | null }> {
    const userId = this.auth.user()?.id;
    if (!userId) return { error: new Error('Not authenticated'), cardId: null, masterCardId: null };

    let masterCardId = formData.masterCardId;

    if (!masterCardId) {
      const { data: newMaster, error: masterError } = await this.supabase
        .from('master_card_definitions')
        .insert({
          set_id: formData.setId || null,
          player: formData.player,
          card_number: formData.cardNumber || null,
          serial_max: formData.serialMax || null,
          is_rookie: formData.isRookie,
          is_auto: formData.isAuto,
          is_patch: formData.isPatch,
          is_ssp: formData.isSSP,
        })
        .select('id')
        .single();

      if (masterError) return { error: masterError, cardId: null, masterCardId: null };
      masterCardId = newMaster.id;
    }

    const { data, error } = await this.supabase
      .from('user_cards')
      .insert({
        master_card_id: masterCardId,
        user_id: userId,
        parallel_id: formData.parallelId || null,
        parallel_name: formData.parallelName || 'Base',
        price_paid: formData.pricePaid,
        serial_number: formData.serialNumber || null,
        is_graded: formData.isGraded,
        grader: formData.isGraded ? formData.grader : null,
        grade_value: formData.isGraded ? formData.gradeValue : null,
      })
      .select('id')
      .single();

    if (!error) await this.loadUserCards();
    return { error, cardId: data?.id ?? null, masterCardId: masterCardId ?? null };
  }

  /** Batch-commit staged cards from a scanner session. price_paid left null for later editing. */
  async batchAddStagedCards(cards: StagedCardPayload[]): Promise<{ error: any; count: number }> {
    const userId = this.auth.user()?.id;
    if (!userId) return { error: new Error('Not authenticated'), count: 0 };

    const rows = cards.map(c => ({
      master_card_id: c.masterCardId,
      user_id: userId,
      parallel_id: c.parallelId,
    }));

    const { error } = await this.supabase.from('user_cards').insert(rows);
    if (!error) await this.loadUserCards();
    return { error, count: error ? 0 : rows.length };
  }

  /** Commit a manual bulk-add session. Creates missing master cards then batch-inserts user_cards. */
  async commitBulkCards(cards: BulkStagedCard[]): Promise<{ error: any; count: number }> {
    const userId = this.auth.user()?.id;
    if (!userId) return { error: new Error('Not authenticated'), count: 0 };

    // Resolve master card IDs for any new cards (no existing masterCardId)
    const newCards = cards.filter(c => !c.masterCardId);
    const tempIdToMasterCardId = new Map<string, string>();

    if (newCards.length > 0) {
      const { data: masters, error: masterError } = await this.supabase
        .from('master_card_definitions')
        .insert(newCards.map(c => ({
          set_id: c.setId,
          player: c.player,
          card_number: c.cardNumber || null,
          serial_max: c.serialMax || null,
          is_rookie: c.isRookie,
          is_auto: c.isAuto,
          is_patch: c.isPatch,
          is_ssp: false,
        })))
        .select('id');
      if (masterError) return { error: masterError, count: 0 };
      newCards.forEach((c, i) => tempIdToMasterCardId.set(c.tempId, (masters as any[])[i].id));
    }

    const rows = cards.map(c => ({
      master_card_id: c.masterCardId ?? tempIdToMasterCardId.get(c.tempId)!,
      user_id: userId,
      parallel_id: c.parallelId || null,
      parallel_name: c.parallelName || 'Base',
      price_paid: c.pricePaid,
      serial_number: c.serialNumber || null,
      is_graded: c.isGraded,
      grader: c.isGraded ? c.grader || null : null,
      grade_value: c.isGraded ? c.gradeValue || null : null,
    }));

    const { error } = await this.supabase.from('user_cards').insert(rows);
    if (!error) {
      await this.loadUserCards();
      // Fire-and-forget image fetch for each master card (safe to call multiple times)
      const masterCardIds = cards.map(c => c.masterCardId ?? tempIdToMasterCardId.get(c.tempId)!).filter(Boolean);
      for (const id of masterCardIds) this.fetchCardImage(id);
    }
    return { error, count: error ? 0 : rows.length };
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

  async updateCard(cardId: string, patch: {
    pricePaid?: number | null;
    serialNumber?: string | null;
    isGraded?: boolean;
    grader?: string | null;
    gradeValue?: string | null;
    parallelId?: string | null;
    parallelName?: string;
  }): Promise<{ error: any }> {
    const row: Record<string, any> = {};
    if ('pricePaid'    in patch) row['price_paid']    = patch.pricePaid;
    if ('serialNumber' in patch) row['serial_number'] = patch.serialNumber || null;
    if ('isGraded'     in patch) row['is_graded']     = patch.isGraded;
    if ('grader'       in patch) row['grader']        = patch.grader;
    if ('gradeValue'   in patch) row['grade_value']   = patch.gradeValue;
    if ('parallelId'   in patch) row['parallel_id']   = patch.parallelId;
    if ('parallelName' in patch) row['parallel_name'] = patch.parallelName;

    const { error } = await this.supabase
      .from('user_cards')
      .update(row)
      .eq('id', cardId);

    if (!error) await this.loadUserCards();
    return { error };
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

      const res = await fetch(`${environment.apiUrl}/api/comps/card-value`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${session.access_token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ cardId }),
      });

      if (res.ok) {
        const { value } = await res.json();
        // Patch just this card's value in-memory — avoids re-sorting the whole list
        this.cards.update(cards =>
          cards.map(c => c.id === cardId ? { ...c, currentValue: value ?? 0 } : c)
        );
      }
    } catch (e) {
      console.error('[CardsService] fetchMarketValue error:', e);
    } finally {
      this.valuingCardIds.update(ids => { const n = new Set(ids); n.delete(cardId); return n; });
    }
  }
}
