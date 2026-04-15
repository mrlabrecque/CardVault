import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TagModule } from 'primeng/tag';
import { LotService } from '../../../core/services/lot';

@Component({
  selector: 'app-lot-basket',
  standalone: true,
  imports: [CommonModule, TagModule],
  templateUrl: './lot-basket.html',
  styleUrl: './lot-basket.scss',
})
export class LotBasket {
  readonly lot = inject(LotService);

  onSliderChange(event: Event) {
    this.lot.pct.set(+(event.target as HTMLInputElement).value);
  }

  pctLabel(): string {
    const pct = this.lot.pct();
    if (pct < 100) return `${pct}% — Discount`;
    if (pct > 100) return `${pct}% — Premium`;
    return '100% — Market Value';
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

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Football: '🏈', Hockey: '🏒', Basketball: '🏀', Baseball: '⚾',
    };
    return map[sport] ?? '🃏';
  }
}
