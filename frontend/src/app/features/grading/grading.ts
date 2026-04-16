import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule, NgTemplateOutlet } from '@angular/common';
import { RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { CardsService } from '../../core/services/cards';
import { AuthService } from '../../core/services/auth';
import { environment } from '../../../environments/environment';

export interface GradingResult {
  psa9Avg: number;
  psa10Avg: number;
  psa9Count: number;
  psa10Count: number;
}

export interface GradingCard {
  id: string;
  player: string;
  year: number;
  set: string;
  checklist: string | null;
  parallel: string;
  sport: string;
  cardNumber: string | null;
  pricePaid: number;
  currentValue: number;
  imageUrl: string | null;
  rookie: boolean;
  autograph: boolean;
  memorabilia: boolean;
  result: GradingResult | null;
  loading: boolean;
  error: boolean;
}

type Tier    = 'grade' | 'borderline' | 'skip' | 'pending';
type SortOpt = 'value-desc' | 'player' | 'profit-desc';
type TierFilter = 'all' | Tier;

@Component({
  selector: 'app-grading',
  standalone: true,
  imports: [CommonModule, NgTemplateOutlet, RouterLink, FormsModule],
  templateUrl: './grading.html',
  styleUrl: './grading.scss',
})
export class Grading implements OnInit {
  private cardsService = inject(CardsService);
  private auth = inject(AuthService);

  gradingFee   = signal(40);
  gradingCards = signal<GradingCard[]>([]);

  searchQuery    = signal('');
  activeFilters  = signal<Set<string>>(new Set());
  sortBy         = signal<SortOpt>('value-desc');
  tierFilter     = signal<TierFilter>('all');

  sortOptions: { value: SortOpt; label: string }[] = [
    { value: 'value-desc',  label: 'Value' },
    { value: 'player',      label: 'Player A–Z' },
    { value: 'profit-desc', label: 'PSA 9 Profit' },
  ];

  tierFilterOptions: { value: TierFilter; label: string }[] = [
    { value: 'all',        label: 'All' },
    { value: 'grade',      label: 'Grade It' },
    { value: 'borderline', label: 'Borderline' },
    { value: 'skip',       label: 'Skip It' },
    { value: 'pending',    label: 'Not Analyzed' },
  ];

  filterConfig = [
    { key: 'rookie',      label: 'RC' },
    { key: 'autograph',   label: 'AUTO' },
    { key: 'memorabilia', label: 'PATCH' },
  ];

  analyzedCount = computed(() => this.gradingCards().filter(c => c.result !== null).length);

  displayCards = computed(() => {
    const q       = this.searchQuery().toLowerCase();
    const filters = this.activeFilters();
    const sort    = this.sortBy();
    const tf      = this.tierFilter();

    let cards = this.gradingCards().filter(gc => {
      if (q && !gc.player.toLowerCase().includes(q) && !gc.set.toLowerCase().includes(q) && !gc.sport.toLowerCase().includes(q)) return false;
      if (filters.has('rookie')      && !gc.rookie)      return false;
      if (filters.has('autograph')   && !gc.autograph)   return false;
      if (filters.has('memorabilia') && !gc.memorabilia) return false;
      if (tf !== 'all' && this.tier(gc) !== tf)          return false;
      return true;
    });

    cards = [...cards].sort((a, b) => {
      if (sort === 'player')      return a.player.localeCompare(b.player);
      if (sort === 'profit-desc') return this.psa9Profit(b) - this.psa9Profit(a);
      return (b.currentValue ?? 0) - (a.currentValue ?? 0);
    });

    return cards;
  });

  private readonly storageKey = 'grading_results';

  private loadCache(): Record<string, GradingResult> {
    try { return JSON.parse(localStorage.getItem(this.storageKey) ?? '{}'); } catch { return {}; }
  }

  private saveToCache(cardId: string, result: GradingResult) {
    const cache = this.loadCache();
    cache[cardId] = result;
    localStorage.setItem(this.storageKey, JSON.stringify(cache));
  }

  ngOnInit() {
    const raw = this.cardsService.cards()
      .filter(c => !c.isGraded)
      .sort((a, b) => (b.currentValue ?? 0) - (a.currentValue ?? 0));

    const cache = this.loadCache();

    this.gradingCards.set(raw.map(c => ({
      id:           c.id,
      player:       c.player,
      year:         c.year,
      set:          c.set,
      checklist:    c.checklist,
      parallel:     c.parallel,
      sport:        c.sport,
      cardNumber:   c.cardNumber,
      pricePaid:    c.pricePaid,
      currentValue: c.currentValue,
      imageUrl:     c.imageUrl,
      rookie:       c.rookie,
      autograph:    c.autograph,
      memorabilia:  c.memorabilia,
      result:       cache[c.id] ?? null,
      loading:      false,
      error:        false,
    })));
  }

  toggleFilter(key: string) {
    this.activeFilters.update(s => {
      const next = new Set(s);
      next.has(key) ? next.delete(key) : next.add(key);
      return next;
    });
  }

  async analyze(cardId: string) {
    this.gradingCards.update(cards =>
      cards.map(gc => gc.id === cardId ? { ...gc, loading: true, error: false } : gc)
    );

    const session = await this.auth.getSession();
    if (!session) return;

    try {
      const res = await fetch(`${environment.apiUrl}/api/grading/analyze/${cardId}`, {
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      if (!res.ok) throw new Error('Failed');
      const data = await res.json();

      this.gradingCards.update(cards =>
        cards.map(gc => gc.id === cardId
          ? {
              ...gc,
              loading: false,
              result: (() => {
                const r: GradingResult = {
                  psa9Avg:    data.psa9.avg,
                  psa10Avg:   data.psa10.avg,
                  psa9Count:  data.psa9.count,
                  psa10Count: data.psa10.count,
                };
                this.saveToCache(cardId, r);
                return r;
              })(),
            }
          : gc
        )
      );
    } catch {
      this.gradingCards.update(cards =>
        cards.map(gc => gc.id === cardId ? { ...gc, loading: false, error: true } : gc)
      );
    }
  }

  psa9Profit(gc: GradingCard): number {
    if (!gc.result) return -Infinity;
    return gc.result.psa9Avg - this.gradingFee() - gc.pricePaid;
  }

  psa10Profit(gc: GradingCard): number {
    if (!gc.result) return -Infinity;
    return gc.result.psa10Avg - this.gradingFee() - gc.pricePaid;
  }

  tier(gc: GradingCard): Tier {
    if (gc.loading || !gc.result) return 'pending';
    const profit = gc.result.psa9Count > 0
      ? this.psa9Profit(gc)
      : gc.result.psa10Count > 0
        ? this.psa10Profit(gc)
        : null;
    if (profit === null) return 'skip';
    if (profit > 25)  return 'grade';
    if (profit >= 0)  return 'borderline';
    return 'skip';
  }

  tierLabel(t: Tier): string {
    return { grade: 'Grade It', borderline: 'Borderline', skip: 'Skip It', pending: '' }[t];
  }

  tierBadgeClass(t: Tier): string {
    return {
      grade:      'bg-emerald-100 text-emerald-700',
      borderline: 'bg-amber-100 text-amber-700',
      skip:       'bg-red-100 text-red-500',
      pending:    '',
    }[t];
  }

  formatProfit(val: number): string {
    const abs = Math.abs(val);
    return (val >= 0 ? '+' : '-') + '$' + abs.toFixed(2);
  }

  profitClass(val: number): string {
    if (val > 25)  return 'text-emerald-600 font-semibold';
    if (val >= 0)  return 'text-amber-600 font-semibold';
    return 'text-red-500 font-semibold';
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Basketball: '🏀', Baseball: '⚾', Football: '🏈', Soccer: '⚽', Hockey: '🏒',
    };
    return map[sport] ?? '🃏';
  }
}
