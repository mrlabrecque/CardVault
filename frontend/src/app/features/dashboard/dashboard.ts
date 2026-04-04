import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ChartModule } from 'primeng/chart';

interface TopCard {
  player: string;
  set: string;
  year: number;
  grade: string;
  value: number;
}

@Component({
  selector: 'app-dashboard',
  imports: [CommonModule, ChartModule],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.scss',
})
export class Dashboard {
  stats = [
    { label: 'Total Value', value: '$12,450', delta: null, icon: 'pi-wallet', color: 'bg-[#800020]' },
    { label: 'P / L', value: '+$2,130', delta: '+20.6%', icon: 'pi-chart-line', color: 'bg-emerald-500' },
    { label: 'Cards', value: '147', delta: null, icon: 'pi-th-large', color: 'bg-[#800020]/70' },
  ];

  topCards: TopCard[] = [
    { player: 'Patrick Mahomes', set: 'Panini Prizm', year: 2017, grade: 'PSA 10', value: 1200 },
    { player: 'Connor McDavid', set: 'Upper Deck Young Guns', year: 2015, grade: 'BGS 9.5', value: 980 },
    { player: 'Luka Dončić', set: 'Panini Prizm Silver', year: 2018, grade: 'PSA 9', value: 740 },
    { player: 'Ronald Acuña Jr.', set: 'Topps Chrome RC', year: 2018, grade: 'PSA 10', value: 560 },
    { player: 'Josh Allen', set: 'Panini Optic', year: 2018, grade: 'PSA 9', value: 410 },
  ];

  sportChartData = {
    labels: ['Football', 'Hockey', 'Basketball', 'Baseball'],
    datasets: [
      {
        data: [52, 28, 15, 5],
        backgroundColor: ['#3b82f6', '#8b5cf6', '#10b981', '#f59e0b'],
        hoverOffset: 6,
      },
    ],
  };

  sportChartOptions = {
    cutout: '70%',
    plugins: {
      legend: {
        position: 'bottom',
        labels: { padding: 16, font: { size: 12 } },
      },
    },
  };
}
