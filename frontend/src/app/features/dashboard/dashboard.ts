import { Component, inject, computed, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
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
  imports: [CommonModule, RouterLink, ChartModule],
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

  bottomView = signal<'top-cards' | 'top-players'>('top-cards');

  topPlayers = computed(() => {
    const counts = new Map<string, number>();
    for (const c of this.cards()) {
      if (c.player) counts.set(c.player, (counts.get(c.player) ?? 0) + 1);
    }
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([player, count]) => ({ player, count }));
  });

  selectedStat = signal<'cards' | 'value' | 'pl'>('cards');
  chartView   = signal<'breakdown' | 'timeline'>('breakdown');

  chartTitle = computed(() => {
    const stat = this.selectedStat();
    const view = this.chartView();
    const statLabel = { cards: 'Cards', value: 'Value', pl: 'P / L' }[stat];
    const viewLabel = { breakdown: 'by Sport', timeline: 'Over Time' }[view];
    return `${statLabel} ${viewLabel}`;
  });

  breakdownData = computed(() => {
    const stat = this.selectedStat();
    const totals: Record<string, number> = {};
    for (const c of this.cards()) {
      if (!c.sport) continue;
      if (stat === 'cards') totals[c.sport] = (totals[c.sport] ?? 0) + 1;
      else if (stat === 'value') totals[c.sport] = (totals[c.sport] ?? 0) + (c.currentValue ?? 0);
      else totals[c.sport] = (totals[c.sport] ?? 0) + ((c.currentValue ?? 0) - (c.pricePaid ?? 0));
    }
    const labels = Object.keys(totals);
    return {
      labels,
      datasets: [{
        data: labels.map(s => totals[s]),
        backgroundColor: labels.map(s => SPORT_COLORS[s] ?? '#94a3b8'),
        hoverOffset: 6,
      }],
    };
  });

  timelineData = computed(() => {
    const stat = this.selectedStat();
    const sorted = [...this.cards()]
      .filter(c => c.createdAt)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt));

    const byDate = new Map<string, number>();
    for (const c of sorted) {
      const date = c.createdAt.slice(0, 10);
      const val = stat === 'cards' ? 1
        : stat === 'value' ? (c.currentValue ?? 0)
        : (c.currentValue ?? 0) - (c.pricePaid ?? 0);
      byDate.set(date, (byDate.get(date) ?? 0) + val);
    }

    const dates = [...byDate.keys()].sort();
    let running = 0;
    const data = dates.map(d => { running += byDate.get(d)!; return +running.toFixed(2); });
    const labels = dates.map(d => {
      const dt = new Date(d + 'T12:00:00');
      return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    });

    return {
      labels,
      datasets: [{
        data,
        borderColor: '#800020',
        backgroundColor: 'rgba(128,0,32,0.08)',
        fill: true,
        tension: 0.4,
        pointRadius: dates.length > 20 ? 0 : 3,
        pointHoverRadius: 5,
      }],
    };
  });

  breakdownOptions = {
    cutout: '70%',
    plugins: { legend: { position: 'bottom', labels: { padding: 16, font: { size: 12 } } } },
  };

  timelineOptions = computed(() => {
    const stat = this.selectedStat();
    const prefix = stat === 'cards' ? '' : '$';
    return {
      plugins: { legend: { display: false } },
      scales: {
        x: { grid: { display: false }, ticks: { font: { size: 10 }, maxTicksLimit: 8 } },
        y: {
          ticks: {
            font: { size: 10 },
            callback: (v: number) => `${prefix}${stat === 'cards' ? v : v.toLocaleString()}`,
          },
        },
      },
    };
  });

  async ngOnInit() {
    await this.cardsService.loadUserCards();
    this.loading.set(false);
  }
}
