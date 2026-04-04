import { Injectable, signal } from '@angular/core';

export interface Card {
  id: string;
  player: string;
  sport: string;
  set: string;
  year: number;
  parallel: string;
  grade: string;
  pricePaid: number;
  currentValue: number;
  rookie: boolean;
  autograph: boolean;
  memorabilia: boolean;
}

@Injectable({ providedIn: 'root' })
export class CardsService {
  cards = signal<Card[]>([
    { id: '1', player: 'Patrick Mahomes',   sport: 'Football',   set: 'Panini Prizm',          year: 2017, parallel: 'Silver Prizm', grade: 'PSA 10',  pricePaid: 600, currentValue: 1200, rookie: true,  autograph: false, memorabilia: false },
    { id: '2', player: 'Connor McDavid',    sport: 'Hockey',     set: 'Upper Deck Young Guns', year: 2015, parallel: 'Base',         grade: 'BGS 9.5', pricePaid: 750, currentValue: 980,  rookie: true,  autograph: false, memorabilia: false },
    { id: '3', player: 'Luka Dončić',       sport: 'Basketball', set: 'Panini Prizm',          year: 2018, parallel: 'Silver',       grade: 'PSA 9',   pricePaid: 500, currentValue: 740,  rookie: true,  autograph: true,  memorabilia: false },
    { id: '4', player: 'Ronald Acuña Jr.',  sport: 'Baseball',   set: 'Topps Chrome',          year: 2018, parallel: 'Refractor',    grade: 'PSA 10',  pricePaid: 300, currentValue: 560,  rookie: true,  autograph: false, memorabilia: false },
    { id: '5', player: 'Josh Allen',        sport: 'Football',   set: 'Panini Optic',          year: 2018, parallel: 'Holo',         grade: 'PSA 9',   pricePaid: 280, currentValue: 410,  rookie: false, autograph: true,  memorabilia: true  },
    { id: '6', player: 'Nathan MacKinnon',  sport: 'Hockey',     set: 'Upper Deck',            year: 2013, parallel: 'Base',         grade: 'PSA 10',  pricePaid: 200, currentValue: 320,  rookie: true,  autograph: false, memorabilia: false },
    { id: '7', player: 'Victor Wembanyama', sport: 'Basketball', set: 'Panini Prizm',          year: 2023, parallel: 'Gold Prizm',   grade: 'PSA 10',  pricePaid: 800, currentValue: 950,  rookie: true,  autograph: true,  memorabilia: true  },
  ]);

  getById(id: string): Card | undefined {
    return this.cards().find(c => c.id === id);
  }
}
