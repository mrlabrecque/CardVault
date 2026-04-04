import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';
import { CardsService } from '../../../core/services/cards';
import { UiService } from '../../../core/services/ui';

export type CardFilter = 'rookie' | 'autograph' | 'memorabilia';

@Component({
  selector: 'app-collection-list',
  imports: [CommonModule, FormsModule, RouterLink, ButtonModule, InputTextModule, TagModule],
  templateUrl: './collection-list.html',
  styleUrl: './collection-list.scss',
})
export class CollectionList implements OnInit {
  private cardsService = inject(CardsService);
  private ui = inject(UiService);

  searchQuery = signal('');
  textFilters = signal<string[]>([]);
  activeFilters = signal<Set<CardFilter>>(new Set());
  gradeFilters = signal<Set<string>>(new Set());

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

  ngOnInit() {
    this.cardsService.loadUserCards();
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

  pl(card: { pricePaid: number; currentValue: number }): number {
    return card.currentValue - card.pricePaid;
  }

  plPercent(card: { pricePaid: number; currentValue: number }): string {
    if (!card.pricePaid) return '—';
    const pct = ((card.currentValue - card.pricePaid) / card.pricePaid) * 100;
    return (pct >= 0 ? '+' : '') + pct.toFixed(0) + '%';
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Football: '🏈', Hockey: '🏒', Basketball: '🏀', Baseball: '⚾',
    };
    return map[sport] ?? '🃏';
  }
}
