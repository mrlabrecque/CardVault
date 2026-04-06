import { Injectable, signal } from '@angular/core';
import { SetRecord, ChecklistRecord, SetParallel } from './sets';

export interface AddCardPrefill {
  player?: string;
  cardNumber?: string;
  set?: SetRecord;
  checklist?: ChecklistRecord;
  checklists?: ChecklistRecord[];  // all checklists for the set
  parallels?: SetParallel[];       // all parallels for the set
}

@Injectable({ providedIn: 'root' })
export class UiService {
  readonly addCardOpen    = signal(false);
  readonly addCardPrefill = signal<AddCardPrefill | null>(null);
}
