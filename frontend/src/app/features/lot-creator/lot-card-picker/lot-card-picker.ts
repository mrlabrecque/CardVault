import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TagModule } from 'primeng/tag';
import { Card, CardsService } from '../../../core/services/cards';
import { LotService } from '../../../core/services/lot';
import { CardFilter } from '../../collection/collection-list/collection-list';

@Component({
  selector: 'app-lot-card-picker',
  standalone: true,
  imports: [CommonModule, TagModule],
  templateUrl: './lot-card-picker.html',
  styleUrl: './lot-card-picker.scss',
})
export class LotCardPicker {
  readonly cardsService = inject(CardsService);
  readonly lot = inject(LotService);

  searchQuery = signal('');

  activeFilters = signal<Set<CardFilter>>(new Set());

  filterConfig: { key: CardFilter; label: string }[] = [
    { key: 'rookie',      label: 'RC' },
    { key: 'autograph',   label: 'AUTO' },
    { key: 'memorabilia', label: 'PATCH' },
  ];

  filtered = computed(() => {
    const q = this.searchQuery().toLowerCase();
    const filters = this.activeFilters();
    return this.cardsService.cards().filter(c => {
      if (q && !c.player.toLowerCase().includes(q)
             && !c.set.toLowerCase().includes(q)
             && !c.sport.toLowerCase().includes(q)) return false;
      if (filters.has('rookie')      && !c.rookie)      return false;
      if (filters.has('autograph')   && !c.autograph)   return false;
      if (filters.has('memorabilia') && !c.memorabilia) return false;
      return true;
    }).sort((a, b) => b.currentValue - a.currentValue);
  });

  toggleFilter(key: CardFilter) {
    this.activeFilters.update(prev => {
      const next = new Set(prev);
      next.has(key) ? next.delete(key) : next.add(key);
      return next;
    });
  }

  isFilterActive(key: CardFilter): boolean {
    return this.activeFilters().has(key);
  }

  onSearchInput(event: Event) {
    this.searchQuery.set((event.target as HTMLInputElement).value);
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Football: '🏈', Hockey: '🏒', Basketball: '🏀', Baseball: '⚾',
    };
    return map[sport] ?? '🃏';
  }

  serialLabel(serialNumber: string | null, serialMax: number | null): string {
    if (serialNumber && serialMax) return `${serialNumber}/${serialMax}`;
    if (serialNumber) return serialNumber;
    if (serialMax) return `/${serialMax}`;
    return '';
  }

  serialTagClass(serialMax: number | null): string {
    if (serialMax === 1)                             return 'bg-gradient-to-r from-amber-400 to-yellow-300 text-amber-900 shadow-sm ring-1 ring-amber-400/50';
    if (serialMax !== null && serialMax <= 5)        return 'bg-purple-600 text-white shadow-sm ring-1 ring-purple-400/40';
    if (serialMax !== null && serialMax <= 10)       return 'bg-rose-600 text-white';
    if (serialMax !== null && serialMax <= 25)       return 'bg-orange-500 text-white';
    if (serialMax !== null && serialMax <= 50)       return 'bg-blue-500 text-white';
    if (serialMax !== null && serialMax <= 99)       return 'bg-sky-400 text-white';
    if (serialMax !== null && serialMax <= 199)      return 'bg-slate-400 text-white';
    return 'bg-gray-100 text-gray-500';
  }
}
