import { Component, inject, computed, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ChartModule } from 'primeng/chart';
import { CardsService } from '../../core/services/cards';

const SPORT_COLORS: Record<string, string> = {
  Basketball: '#10b981',
  Football:   '#3b82f6',
  Baseball:   '#f59e0b',
  Soccer:     '#8b5cf6',
  Hockey:     '#ef4444',
};

@Component({
  selector: 'app-dashboard',
  imports: [CommonModule, ChartModule],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.scss',
})
export class Dashboard implements OnInit {
  private cardsService = inject(CardsService);
  private cards = this.cardsService.cards;

  loading = signal(true);

  totalValue = computed(() =>
    this.cards().reduce((s, c) => s + (c.currentValue ?? 0), 0)
  );

  totalCost = computed(() =>
    this.cards().reduce((s, c) => s + (c.pricePaid ?? 0), 0)
  );

  pl = computed(() => this.totalValue() - this.totalCost());

  plPct = computed(() => {
    const cost = this.totalCost();
    return cost > 0 ? (this.pl() / cost) * 100 : null;
  });

  cardCount = computed(() => this.cards().length);

  topCards = computed(() =>
    [...this.cards()]
      .filter(c => (c.currentValue ?? 0) > 0)
      .sort((a, b) => (b.currentValue ?? 0) - (a.currentValue ?? 0))
      .slice(0, 5)
  );

  sportChartData = computed(() => {
    const counts: Record<string, number> = {};
    for (const c of this.cards()) {
      if (c.sport) counts[c.sport] = (counts[c.sport] ?? 0) + 1;
    }
    const labels = Object.keys(counts);
    return {
      labels,
      datasets: [{
        data: labels.map(s => counts[s]),
        backgroundColor: labels.map(s => SPORT_COLORS[s] ?? '#94a3b8'),
        hoverOffset: 6,
      }],
    };
  });

  sportChartOptions = {
    cutout: '70%',
    plugins: {
      legend: {
        position: 'bottom',
        labels: { padding: 16, font: { size: 12 } },
      },
    },
  };

  async ngOnInit() {
    await this.cardsService.loadUserCards();
    this.loading.set(false);
  }
}
