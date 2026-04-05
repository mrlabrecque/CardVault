import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';
import { Card, CardsService } from '../../../core/services/cards';
import { UiService } from '../../../core/services/ui';

export type CardFilter = 'rookie' | 'autograph' | 'memorabilia';

export interface CardStack {
  key: string;
  masterCardId: string;
  player: string;
  cardNumber: string | null;
  sport: string;
  set: string;
  year: number;
  parallel: string;
  grade: string;
  isGraded: boolean;
  gradeValue: string | null;
  grader: string | null;
  cards: Card[];
  qty: number;
  totalCost: number;
  avgCost: number;
  totalValue: number;
  marketValuePerCard: number;
  rookie: boolean;
  autograph: boolean;
  memorabilia: boolean;
}

@Component({
  selector: 'app-collection-list',
  imports: [CommonModule, FormsModule, RouterLink, ButtonModule, InputTextModule, TagModule],
  templateUrl: './collection-list.html',
  styleUrl: './collection-list.scss',
})
export class CollectionList implements OnInit {
  private cardsService = inject(CardsService);
  private ui = inject(UiService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  searchQuery = signal('');
  textFilters = signal<string[]>([]);
  activeFilters = signal<Set<CardFilter>>(new Set());
  gradeFilters = signal<Set<string>>(new Set());
  expandedKeys = signal<Set<string>>(new Set());

  filterConfig: { key: CardFilter; label: string; severity: 'info' | 'warn' | 'success' }[] = [
    { key: 'rookie',      label: 'RC',    severity: 'info' },
    { key: 'autograph',   label: 'AUTO',  severity: 'warn' },
    { key: 'memorabilia', label: 'PATCH', severity: 'success' },
  ];

  filtered = computed(() => {
    const q = this.searchQuery().toLowerCase();
    const textChips = this.textFilters();
    const filters = this.activeFilters();
    const grades = this.gradeFilters();
    return this.cardsService.cards().filter(c => {
      if (q && !c.player.toLowerCase().includes(q) && !c.set.toLowerCase().includes(q) && !c.sport.toLowerCase().includes(q)) return false;
      for (const chip of textChips) {
        const t = chip.toLowerCase();
        if (!c.player.toLowerCase().includes(t) && !c.set.toLowerCase().includes(t) && !c.sport.toLowerCase().includes(t)) return false;
      }
      if (filters.has('rookie')      && !c.rookie)      return false;
      if (filters.has('autograph')   && !c.autograph)   return false;
      if (filters.has('memorabilia') && !c.memorabilia) return false;
      if (grades.size > 0 && !grades.has(c.grade))      return false;
      return true;
    });
  });

  stacks = computed(() => {
    const map = new Map<string, CardStack>();
    for (const card of this.filtered()) {
      const key = `${card.masterCardId}|${card.isGraded}|${card.gradeValue ?? ''}`;
      if (!map.has(key)) {
        map.set(key, {
          key,
          masterCardId: card.masterCardId,
          player: card.player,
          cardNumber: card.cardNumber,
          sport: card.sport,
          set: card.set,
          year: card.year,
          parallel: card.parallel,
          grade: card.grade,
          isGraded: card.isGraded,
          gradeValue: card.gradeValue,
          grader: card.grader,
          cards: [],
          qty: 0,
          totalCost: 0,
          avgCost: 0,
          totalValue: 0,
          marketValuePerCard: 0,
          rookie: card.rookie,
          autograph: card.autograph,
          memorabilia: card.memorabilia,
        });
      }
      const stack = map.get(key)!;
      stack.cards.push(card);
      stack.qty++;
      stack.totalCost += card.pricePaid;
      stack.totalValue += card.currentValue;
    }
    for (const stack of map.values()) {
      stack.avgCost = stack.qty > 0 ? stack.totalCost / stack.qty : 0;
      stack.marketValuePerCard = stack.qty > 0 ? stack.totalValue / stack.qty : 0;
    }
    return Array.from(map.values());
  });

  totalCardCount = computed(() => this.filtered().length);

  ngOnInit() {
    this.cardsService.loadUserCards();
    const q = this.route.snapshot.queryParamMap.get('q');
    if (q) this.textFilters.set([q]);
  }

  openAddCard() {
    this.ui.addCardOpen.set(true);
  }

  commitSearch() {
    const q = this.searchQuery().trim();
    if (!q) return;
    if (!this.textFilters().includes(q)) {
      this.textFilters.update(prev => [...prev, q]);
    }
    this.searchQuery.set('');
  }

  removeTextFilter(chip: string) {
    this.textFilters.update(prev => prev.filter(t => t !== chip));
  }

  toggleFilter(key: CardFilter) {
    this.activeFilters.update(prev => {
      const next = new Set(prev);
      next.has(key) ? next.delete(key) : next.add(key);
      return next;
    });
  }

  removeFilter(key: CardFilter) {
    this.activeFilters.update(prev => { const next = new Set(prev); next.delete(key); return next; });
  }

  isFilterActive(key: CardFilter): boolean {
    return this.activeFilters().has(key);
  }

  toggleGradeFilter(grade: string) {
    this.gradeFilters.update(prev => {
      const next = new Set(prev);
      next.has(grade) ? next.delete(grade) : next.add(grade);
      return next;
    });
  }

  removeGradeFilter(grade: string) {
    this.gradeFilters.update(prev => { const next = new Set(prev); next.delete(grade); return next; });
  }

  isGradeFilterActive(grade: string): boolean {
    return this.gradeFilters().has(grade);
  }

  toggleStack(stack: CardStack) {
    if (stack.qty === 1) {
      this.router.navigate(['/collection', stack.cards[0].id]);
      return;
    }
    this.expandedKeys.update(prev => {
      const next = new Set(prev);
      next.has(stack.key) ? next.delete(stack.key) : next.add(stack.key);
      return next;
    });
  }

  isExpanded(key: string): boolean {
    return this.expandedKeys().has(key);
  }

  stackPl(stack: CardStack): number {
    return stack.totalValue - stack.totalCost;
  }

  stackPlPct(stack: CardStack): string {
    if (!stack.totalCost) return '—';
    const pct = ((stack.totalValue - stack.totalCost) / stack.totalCost) * 100;
    return (pct >= 0 ? '+' : '') + pct.toFixed(0) + '%';
  }

  cardPl(card: Card): number {
    return card.currentValue - card.pricePaid;
  }

  readonly valuingCardIds = this.cardsService.valuingCardIds;
  pendingDeleteId = signal<string | null>(null);
  deletingId = signal<string | null>(null);

  isStackValuing(stack: CardStack): boolean {
    const ids = this.valuingCardIds();
    return stack.cards.some(c => ids.has(c.id));
  }

  refetchStack(stack: CardStack, event: Event) {
    event.stopPropagation();
    for (const card of stack.cards) {
      this.cardsService.fetchMarketValue(card.id);
    }
  }

  requestDelete(cardId: string, event: Event) {
    event.stopPropagation();
    this.pendingDeleteId.set(cardId);
  }

  cancelDelete(event: Event) {
    event.stopPropagation();
    this.pendingDeleteId.set(null);
  }

  async confirmDelete(cardId: string, event: Event) {
    event.stopPropagation();
    this.deletingId.set(cardId);
    await this.cardsService.deleteCard(cardId);
    this.deletingId.set(null);
    this.pendingDeleteId.set(null);
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Football: '🏈', Hockey: '🏒', Basketball: '🏀', Baseball: '⚾',
    };
    return map[sport] ?? '🃏';
  }
}
