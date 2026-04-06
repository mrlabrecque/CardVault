import {
  Component, inject, signal, computed, ViewChild, ElementRef,
  OnDestroy, OnInit
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { ScannerService, ParsedCard } from '../../core/services/scanner';
import { CardsService, MasterCard, StagedCardPayload } from '../../core/services/cards';
import { SetsService, SetRecord, SetParallel, ChecklistRecord } from '../../core/services/sets';
import { UiService } from '../../core/services/ui';

export type ScanState = 'no-session' | 'ready' | 'processing' | 'matched' | 'no-match' | 'discovery';

export interface StagedCard {
  tempId: string;
  masterCard: MasterCard;
  parallelId: string | null;
  parallelName: string;
}

@Component({
  selector: 'app-scanner',
  imports: [CommonModule, FormsModule],
  templateUrl: './scanner.html',
  styleUrl: './scanner.scss',
})
export class Scanner implements OnInit, OnDestroy {
  @ViewChild('videoEl') videoEl!: ElementRef<HTMLVideoElement>;

  private scannerService = inject(ScannerService);
  private cardsService   = inject(CardsService);
  private setsService    = inject(SetsService);
  private router         = inject(Router);
  readonly ui            = inject(UiService);
  private stream: MediaStream | null = null;
  private audioCtx: AudioContext | null = null;

  // ── Session state ────────────────────────────────────────
  scanState = signal<ScanState>('no-session');
  sessionSet = signal<SetRecord | null>(null);
  sessionChecklists = signal<ChecklistRecord[]>([]);
  sessionParallels  = signal<SetParallel[]>([]);
  activeChecklist   = signal<ChecklistRecord | null>(null);

  // ── Set picker (used to start a session) ─────────────────
  setQuery   = signal('');
  setResults = signal<SetRecord[]>([]);
  showSetDropdown = signal(false);
  private setSearchTimer: ReturnType<typeof setTimeout> | null = null;

  // ── OCR / match results ──────────────────────────────────
  parsedCard    = signal<ParsedCard | null>(null);
  matchedCards  = signal<MasterCard[]>([]);
  selectedMatch = signal<MasterCard | null>(null);
  ocrError      = signal<string | null>(null);

  // ── Discovery mode (unknown set detected) ────────────────
  discoveryYear        = signal<number | null>(null);
  discoveryBrand       = signal('');
  discoverySport       = signal('Basketball');
  discoveryReleaseType = signal('Hobby');
  submittingDiscovery  = signal(false);
  readonly sports       = ['Basketball', 'Baseball', 'Football', 'Soccer'];
  readonly releaseTypes = ['Hobby', 'Retail', 'FOTL'];

  // ── Staging list ─────────────────────────────────────────
  stagingList = signal<StagedCard[]>([]);
  stagedCount = computed(() => this.stagingList().length);
  committing  = signal(false);
  commitError = signal<string | null>(null);
  commitSuccess = signal(false);

  // ── Camera ───────────────────────────────────────────────
  cameraError = signal<string | null>(null);

  async ngOnInit() {
    // Camera is started after the user picks a session set (view is rendered then)
  }

  ngOnDestroy() {
    this.stopCamera();
    this.scannerService.clearIndex();
  }

  // ── Session Setup ─────────────────────────────────────────

  onSetQueryChange(value: string) {
    this.setQuery.set(value);
    if (this.setSearchTimer) clearTimeout(this.setSearchTimer);
    if (!value.trim()) { this.setResults.set([]); this.showSetDropdown.set(false); return; }
    this.setSearchTimer = setTimeout(() => this.doSetSearch(value), 250);
  }

  private async doSetSearch(query: string) {
    const results = await this.setsService.searchSets(query);
    this.setResults.set(results);
    this.showSetDropdown.set(results.length > 0);
  }

  async selectSessionSet(set: SetRecord) {
    this.sessionSet.set(set);
    this.setQuery.set('');
    this.showSetDropdown.set(false);

    const checklists = await this.setsService.getChecklists(set.id);
    const baseChecklist = checklists.find(c => c.prefix === null) ?? checklists[0] ?? null;

    const [parallels, masterCards] = await Promise.all([
      baseChecklist ? this.setsService.getParallels(baseChecklist.id) : Promise.resolve([]),
      baseChecklist ? this.cardsService.getMasterCardsForChecklist(baseChecklist.id) : Promise.resolve([]),
    ]);

    this.sessionChecklists.set(checklists);
    this.sessionParallels.set(parallels);
    this.activeChecklist.set(baseChecklist);

    if (baseChecklist) {
      this.scannerService.buildIndex(baseChecklist.id, masterCards);
    }

    this.scanState.set('ready');
    // Small delay so Angular renders the video element before we start the stream
    setTimeout(() => this.startCamera(), 50);
  }

  clearSession() {
    this.stopCamera();
    this.scannerService.clearIndex();
    this.sessionSet.set(null);
    this.sessionChecklists.set([]);
    this.sessionParallels.set([]);
    this.activeChecklist.set(null);
    this.stagingList.set([]);
    this.parsedCard.set(null);
    this.matchedCards.set([]);
    this.selectedMatch.set(null);
    this.scanState.set('no-session');
  }

  // ── Camera ────────────────────────────────────────────────

  private async startCamera() {
    this.cameraError.set(null);
    try {
      // Use `ideal` so desktop browsers fall back to any available camera
      // instead of rejecting the request outright
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
      });
      const video = this.videoEl?.nativeElement;
      if (video) {
        video.srcObject = this.stream;
        await video.play();
        // Wait for actual frame dimensions to be reported before allowing capture
        await new Promise<void>(resolve => {
          if (video.videoWidth > 0) { resolve(); return; }
          video.addEventListener('loadedmetadata', () => resolve(), { once: true });
        });
      }
    } catch (e: any) {
      this.cameraError.set('Camera access denied. Please allow camera permissions and try again.');
    }
  }

  private stopCamera() {
    this.stream?.getTracks().forEach(t => t.stop());
    this.stream = null;
  }

  // ── Capture & OCR ─────────────────────────────────────────

  async capture() {
    if (this.scanState() !== 'ready') return;
    this.scanState.set('processing');
    this.ocrError.set(null);
    this.parsedCard.set(null);
    this.matchedCards.set([]);
    this.selectedMatch.set(null);

    try {
      const imageDataUrl = this.captureFrame();
      const rawText = await this.scannerService.recognize(imageDataUrl);
      const parsed = this.scannerService.parseCardText(rawText);
      this.parsedCard.set(parsed);

      // Check if OCR detected a different set (year/brand mismatch)
      if (parsed.year && parsed.brand) {
        const setYear = this.sessionSet()?.year;
        if (setYear && parsed.year !== setYear) {
          this.discoveryYear.set(parsed.year);
          this.discoveryBrand.set(parsed.brand);
          this.scanState.set('discovery');
          return;
        }
      }

      // Route to correct checklist based on card number prefix
      const targetChecklist = this.scannerService.matchChecklistFromPrefix(
        parsed.numberPrefix,
        this.sessionChecklists()
      );
      if (targetChecklist && targetChecklist.id !== this.activeChecklist()?.id) {
        this.activeChecklist.set(targetChecklist);
        const [cards, parallels] = await Promise.all([
          this.cardsService.getMasterCardsForChecklist(targetChecklist.id),
          this.setsService.getParallels(targetChecklist.id),
        ]);
        this.scannerService.buildIndex(targetChecklist.id, cards);
        this.sessionParallels.set(parallels);
      }

      // Fuzzy match player name
      const matches = this.scannerService.fuzzyMatch(parsed.playerCandidates);
      this.matchedCards.set(matches);

      if (matches.length > 0) {
        this.selectedMatch.set(matches[0]);
        this.scanState.set('matched');
        this.playBeep(800, 0.1);
      } else {
        this.scanState.set('no-match');
        this.playBeep(300, 0.3);
      }
    } catch (e: any) {
      this.ocrError.set('OCR failed. Try again with better lighting.');
      this.scanState.set('ready');
    }
  }

  private captureFrame(): string {
    const video = this.videoEl.nativeElement;
    const w = video.videoWidth;
    const h = video.videoHeight;
    if (w < 100 || h < 100) {
      throw new Error('Camera not ready yet — please wait a moment and try again.');
    }
    const canvas = document.createElement('canvas');
    canvas.width  = w;
    canvas.height = h;
    canvas.getContext('2d')!.drawImage(video, 0, 0);
    return canvas.toDataURL('image/jpeg', 0.85);
  }

  // ── Staging ───────────────────────────────────────────────

  /** Called when user taps a parallel pill — stages the card and resets. */
  stageCard(parallel: SetParallel | null) {
    const card = this.selectedMatch();
    if (!card) return;

    const parallelName = parallel?.name ?? 'Base';
    const isInsert = this.activeChecklist()?.prefix !== null;

    this.stagingList.update(list => [
      {
        tempId: crypto.randomUUID(),
        masterCard: card,
        parallelId: parallel?.id ?? null,
        parallelName,
      },
      ...list,
    ]);

    // Audio: different tone for insert vs base
    this.playBeep(isInsert ? 600 : 900, 0.08);
    setTimeout(() => this.playBeep(isInsert ? 900 : 600, 0.06), 100);

    // Auto-reset after 800ms
    setTimeout(() => {
      this.scanState.set('ready');
      this.parsedCard.set(null);
      this.matchedCards.set([]);
      this.selectedMatch.set(null);
    }, 800);
  }

  /** Stage with Base parallel (no FK) */
  stageAsBase() {
    this.stageCard(null);
  }

  removeStagedCard(tempId: string) {
    this.stagingList.update(list => list.filter(c => c.tempId !== tempId));
  }

  // ── Commit ────────────────────────────────────────────────

  async commitAll() {
    if (this.stagedCount() === 0 || this.committing()) return;
    this.committing.set(true);
    this.commitError.set(null);

    const payloads: StagedCardPayload[] = this.stagingList().map(c => ({
      masterCardId: c.masterCard.id,
      parallelId: c.parallelId,
    }));

    const { error, count } = await this.cardsService.batchAddStagedCards(payloads);

    this.committing.set(false);
    if (error) {
      this.commitError.set(error.message ?? 'Failed to save cards.');
    } else {
      this.stagingList.set([]);
      this.commitSuccess.set(true);
      setTimeout(() => this.commitSuccess.set(false), 3000);
    }
  }

  // ── Discovery Mode ────────────────────────────────────────

  async submitDiscovery() {
    const year = this.discoveryYear();
    const brand = this.discoveryBrand().trim();
    if (!year || !brand) return;

    this.submittingDiscovery.set(true);
    await this.scannerService.submitPendingSet({
      name: brand,
      year,
      sport: this.discoverySport(),
      release_type: this.discoveryReleaseType(),
    });
    this.submittingDiscovery.set(false);
    this.scanState.set('ready');
  }

  dismissDiscovery() {
    this.scanState.set('ready');
  }

  // ── Helpers ───────────────────────────────────────────────

  openManualEntry() {
    const parsed = this.parsedCard();
    this.ui.addCardPrefill.set({
      player:     parsed?.playerCandidates?.[0] || undefined,
      cardNumber: parsed?.cardNumber            || undefined,
      set:        this.sessionSet()             || undefined,
      checklist:  this.activeChecklist()        || undefined,
      checklists: this.sessionChecklists().length ? this.sessionChecklists() : undefined,
      parallels:  this.sessionParallels().length  ? this.sessionParallels()  : undefined,
    });
    this.ui.addCardOpen.set(true);
  }

  dismiss() {
    this.scanState.set('ready');
  }

  goBack() {
    this.router.navigate(['/collection']);
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Basketball: '🏀', Baseball: '⚾', Football: '🏈', Soccer: '⚽',
    };
    return map[sport] ?? '🃏';
  }

  private playBeep(frequency: number, duration: number) {
    try {
      if (!this.audioCtx) this.audioCtx = new AudioContext();
      const osc  = this.audioCtx.createOscillator();
      const gain = this.audioCtx.createGain();
      osc.connect(gain);
      gain.connect(this.audioCtx.destination);
      osc.frequency.value = frequency;
      gain.gain.setValueAtTime(0.25, this.audioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, this.audioCtx.currentTime + duration);
      osc.start(this.audioCtx.currentTime);
      osc.stop(this.audioCtx.currentTime + duration);
    } catch { /* audio not available */ }
  }
}
