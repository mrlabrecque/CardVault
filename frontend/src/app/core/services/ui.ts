import { Injectable, signal } from '@angular/core';
import { ReleaseRecord, SetRecord, SetParallel } from './releases';

export interface AddCardPrefill {
  player?: string;
  cardNumber?: string;
  set?: ReleaseRecord;
  checklist?: SetRecord;
  checklists?: SetRecord[];    // all sets within the release
  parallels?: SetParallel[];   // all parallels for the selected set
}

@Injectable({ providedIn: 'root' })
export class UiService {
  readonly addCardOpen    = signal(false);
  readonly addCardPrefill = signal<AddCardPrefill | null>(null);
}
