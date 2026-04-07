import { Component, inject, signal, computed, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { CardsService, MasterCard, BulkStagedCard } from '../../../core/services/cards';
import { ReleasesService, ReleaseRecord, SetRecord, SetParallel } from '../../../core/services/releases';

const GRADERS = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];
const FALLBACK_PARALLELS = ['Base', 'Silver Prizm', 'Gold Prizm', 'Red Prizm', 'Blue Prizm', 'Holo', 'Refractor', 'Gold Refractor', 'Xfractor', 'Rookie Patch Auto'];

@Component({
  selector: 'app-bulk-add',
  imports: [CommonModule, FormsModule],
  templateUrl: './bulk-add.html',
})
export class BulkAdd {
  private cardsService    = inject(CardsService);
  private releasesService = inject(ReleasesService);
  private router          = inject(Router);

  readonly graders          = GRADERS;
  readonly fallbackParallels = FALLBACK_PARALLELS;

  // ── Session ───────────────────────────────────────────────
  sessionSet        = signal<ReleaseRecord | null>(null);
  sessionChecklists = signal<SetRecord[]>([]);
  activeChecklist   = signal<SetRecord | null>(null);
  activeParallels   = signal<SetParallel[]>([]);

  // ── Box calculator ────────────────────────────────────────
  boxPrice      = signal<number | null>(null);
  boxQty        = signal<number | null>(null);
  pricePerCard  = computed(() => {
    const bp = this.boxPrice();
    const bq = this.boxQty();
    return (bp && bq && bq > 0) ? Math.round((bp / bq) * 100) / 100 : null;
  });

  setQuery        = signal('');
  setResults      = signal<ReleaseRecord[]>([]);
  showSetDropdown = signal(false);
  private setSearchTimer: ReturnType<typeof setTimeout> | null = null;

  // ── Card search ───────────────────────────────────────────
  playerQuery        = signal('');
  playerResults      = signal<MasterCard[]>([]);
  showPlayerDropdown = signal(false);
  noPlayerResults    = signal(false);
  selectedMasterCard = signal<MasterCard | null>(null);
  isNewCard          = signal(false);

  // ── New card definition ───────────────────────────────────
  newPlayer     = signal('');
  newCardNumber = signal('');
  newSerialMax  = signal<number | null>(null);
  newIsRookie   = signal(false);
  newIsAuto     = signal(false);
  newIsPatch    = signal(false);
  newIsSSP      = signal(false);

  // ── Parallel ──────────────────────────────────────────────
  selectedParallelId   = signal<string | null>(null);
  selectedParallelName = signal('Base');
  parallelIsOther      = signal(false);

  // ── User copy ─────────────────────────────────────────────
  pricePaid    = signal<number | null>(null);
  serialNumber = signal('');
  isGraded     = signal(false);
  grader       = signal('PSA');
  gradeValue   = signal('');

  private playerSearchTimer: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    effect(() => {
      const ppc = this.pricePerCard();
      if (ppc !== null) this.pricePaid.set(ppc);
    });
  }

  // ── Staging ───────────────────────────────────────────────
  stagingList   = signal<BulkStagedCard[]>([]);
  stagedCount   = computed(() => this.stagingList().length);
  committing    = signal(false);
  commitError   = signal<string | null>(null);
  commitSuccess = signal(false);

  // ── Computed ──────────────────────────────────────────────
  get cardIsSelected(): boolean {
    return this.selectedMasterCard() !== null || this.isNewCard();
  }

  get canStage(): boolean {
    if (!this.cardIsSelected) return false;
    if (this.isNewCard() && !this.newPlayer().trim()) return false;
    if (!this.pricePaid() || this.pricePaid()! <= 0) return false;
    if (this.isGraded() && !this.gradeValue().trim()) return false;
    return true;
  }

  // ── Set search ────────────────────────────────────────────

  onSetQueryChange(value: string) {
    this.setQuery.set(value);
    if (this.setSearchTimer) clearTimeout(this.setSearchTimer);
    if (!value.trim()) { this.setResults.set([]); this.showSetDropdown.set(false); return; }
    this.setSearchTimer = setTimeout(() => this.doSetSearch(value), 250);
  }

  private async doSetSearch(query: string) {
    const results = await this.releasesService.searchReleases(query);
    this.setResults.set(results);
    this.showSetDropdown.set(results.length > 0);
  }

  async selectSessionSet(release: ReleaseRecord) {
    this.sessionSet.set(release);
    this.setQuery.set('');
    this.showSetDropdown.set(false);
    this.activeChecklist.set(null);
    this.activeParallels.set([]);
    this.boxPrice.set(null);
    this.boxQty.set(null);

    const sets = await this.releasesService.getSets(release.id);
    this.sessionChecklists.set(sets);
    this.resetForm();
  }

  async selectChecklist(s: SetRecord) {
    this.activeChecklist.set(s);
    this.activeParallels.set(await this.releasesService.getParallels(s.id));
    this.resetForm();
  }

  endSession() {
    this.sessionSet.set(null);
    this.sessionChecklists.set([]);
    this.activeChecklist.set(null);
    this.activeParallels.set([]);
    this.stagingList.set([]);
    this.boxPrice.set(null);
    this.boxQty.set(null);
    this.resetForm();
  }

  // ── Card search ───────────────────────────────────────────

  onPlayerQueryChange(value: string) {
    this.playerQuery.set(value);
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.noPlayerResults.set(false);
    if (this.playerSearchTimer) clearTimeout(this.playerSearchTimer);
    if (!value.trim()) { this.playerResults.set([]); this.showPlayerDropdown.set(false); return; }
    this.playerSearchTimer = setTimeout(() => this.doPlayerSearch(value), 250);
  }

  private async doPlayerSearch(query: string) {
    const results = await this.cardsService.searchMasterCards(
      this.activeChecklist()?.id ?? null,
      query
    );
    this.playerResults.set(results);
    this.showPlayerDropdown.set(true);
    this.noPlayerResults.set(results.length === 0);
  }

  selectMasterCard(card: MasterCard) {
    this.selectedMasterCard.set(card);
    this.isNewCard.set(false);
    this.showPlayerDropdown.set(false);
    this.playerQuery.set(card.card_number ? `${card.player} #${card.card_number}` : card.player);
  }

  startNewCard() {
    this.isNewCard.set(true);
    this.selectedMasterCard.set(null);
    this.showPlayerDropdown.set(false);
    const q = this.playerQuery().trim();
    if (q && !q.match(/^\d+$/)) this.newPlayer.set(q);
  }

  clearCardSelection() {
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.playerQuery.set('');
    this.playerResults.set([]);
    this.noPlayerResults.set(false);
  }

  // ── Parallel ──────────────────────────────────────────────

  onParallelChange(value: string) {
    if (value === '__other__') {
      this.parallelIsOther.set(true);
      this.selectedParallelId.set(null);
      this.selectedParallelName.set('');
      return;
    }
    this.parallelIsOther.set(false);
    const match = this.activeParallels().find(p => p.id === value);
    if (match) {
      this.selectedParallelId.set(match.id);
      this.selectedParallelName.set(match.name);
    } else {
      this.selectedParallelId.set(null);
      this.selectedParallelName.set(value === 'base' ? 'Base' : value);
    }
  }

  // ── Stage ─────────────────────────────────────────────────

  stageCard() {
    if (!this.canStage) return;

    const master = this.selectedMasterCard();
    const player = master?.player ?? this.newPlayer().trim();
    const cardNumber = master?.card_number ?? (this.newCardNumber().trim() || null);
    const cl = this.activeChecklist();

    this.stagingList.update(list => [{
      tempId: crypto.randomUUID(),
      masterCardId: master?.id ?? null,
      player,
      cardNumber,
      setId: cl?.id ?? null,
      checklistName: cl?.prefix != null ? cl.name : null,
      parallelId: this.selectedParallelId(),
      parallelName: this.selectedParallelName() || 'Base',
      pricePaid: this.pricePaid()!,
      serialNumber: this.serialNumber(),
      serialMax: this.isNewCard() ? this.newSerialMax() : (master?.serial_max ?? null),
      isRookie: this.isNewCard() ? this.newIsRookie() : (master?.is_rookie ?? false),
      isAuto: this.isNewCard() ? this.newIsAuto() : (master?.is_auto ?? false),
      isPatch: this.isNewCard() ? this.newIsPatch() : (master?.is_patch ?? false),
      isGraded: this.isGraded(),
      grader: this.grader(),
      gradeValue: this.gradeValue(),
    }, ...list]);

    // Fire-and-forget pending parallel if user typed a custom one
    if (this.parallelIsOther() && this.selectedParallelName().trim() && this.sessionSet()) {
      this.releasesService.submitPendingParallel(this.sessionSet()!.id, this.selectedParallelName().trim());
    }

    // Reset card identity + instance fields; keep checklist + parallel context
    this.playerQuery.set('');
    this.playerResults.set([]);
    this.noPlayerResults.set(false);
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.newPlayer.set('');
    this.newCardNumber.set('');
    this.newSerialMax.set(null);
    this.newIsRookie.set(false);
    this.newIsAuto.set(false);
    this.newIsPatch.set(false);
    this.newIsSSP.set(false);
    this.pricePaid.set(this.pricePerCard());
    this.serialNumber.set('');
    this.gradeValue.set('');
  }

  removeStaged(tempId: string) {
    this.stagingList.update(list => list.filter(c => c.tempId !== tempId));
  }

  // ── Commit ────────────────────────────────────────────────

  async commitAll() {
    if (this.stagedCount() === 0 || this.committing()) return;
    this.committing.set(true);
    this.commitError.set(null);

    const { error } = await this.cardsService.commitBulkCards(this.stagingList());
    this.committing.set(false);

    if (error) {
      this.commitError.set(error.message ?? 'Failed to save cards.');
    } else {
      this.stagingList.set([]);
      this.commitSuccess.set(true);
      setTimeout(() => this.commitSuccess.set(false), 3000);
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  private resetForm() {
    this.playerQuery.set('');
    this.playerResults.set([]);
    this.showPlayerDropdown.set(false);
    this.noPlayerResults.set(false);
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.newPlayer.set('');
    this.newCardNumber.set('');
    this.newSerialMax.set(null);
    this.newIsRookie.set(false);
    this.newIsAuto.set(false);
    this.newIsPatch.set(false);
    this.newIsSSP.set(false);
    this.selectedParallelId.set(null);
    this.selectedParallelName.set('Base');
    this.parallelIsOther.set(false);
    this.pricePaid.set(null);
    this.serialNumber.set('');
    this.isGraded.set(false);
    this.grader.set('PSA');
    this.gradeValue.set('');
  }

  goBack() { this.router.navigate(['/collection']); }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Basketball: '🏀', Baseball: '⚾', Football: '🏈', Soccer: '⚽',
    };
    return map[sport] ?? '🃏';
  }

  serialLabel(serialNumber: string, serialMax: number | null): string {
    if (serialNumber && serialMax) return `${serialNumber}/${serialMax}`;
    if (serialNumber) return serialNumber;
    if (serialMax) return `/${serialMax}`;
    return '';
  }

  serialTagClass(serialMax: number | null): string {
    if (serialMax === 1)   return 'bg-gradient-to-r from-amber-400 to-yellow-300 text-amber-900 shadow-sm ring-1 ring-amber-400/50';
    if (serialMax !== null && serialMax <= 5)   return 'bg-purple-600 text-white shadow-sm ring-1 ring-purple-400/40';
    if (serialMax !== null && serialMax <= 10)  return 'bg-rose-600 text-white';
    if (serialMax !== null && serialMax <= 25)  return 'bg-orange-500 text-white';
    if (serialMax !== null && serialMax <= 50)  return 'bg-blue-500 text-white';
    if (serialMax !== null && serialMax <= 99)  return 'bg-sky-400 text-white';
    if (serialMax !== null && serialMax <= 199) return 'bg-slate-400 text-white';
    return 'bg-gray-100 text-gray-500';
  }
}
