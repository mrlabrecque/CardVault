import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

export interface Tool {
  label: string;
  desc: string;
  route: string;
  available: boolean;
}

@Component({
  selector: 'app-tools',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './tools.html',
  styleUrl: './tools.scss',
})
export class Tools {
  tools: Tool[] = [
    {
      label: 'Comps',
      desc: 'Look up recent eBay sold prices for any card.',
      route: '/comps',
      available: true,
    },
    {
      label: 'Lot Creator',
      desc: 'Bundle cards into lots for bulk eBay listings.',
      route: '/lot-creator',
      available: false,
    },
    {
      label: 'Card Import',
      desc: 'Import your collection from a CSV or spreadsheet.',
      route: '/import',
      available: true,
    },
    {
      label: 'Grading',
      desc: 'Grading recommendations based on estimated PSA 10 premiums.',
      route: '/grading',
      available: false,
    },
    {
      label: 'Market Movers',
      desc: 'Surface cards with the biggest recent price changes.',
      route: '/market-movers',
      available: false,
    },
    {
      label: 'Heat Map',
      desc: 'Visual breakdown of your collection by sport, year, and player.',
      route: '/heat-map',
      available: false,
    },
  ];
}
