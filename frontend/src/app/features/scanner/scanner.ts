import {
  Component, inject, signal, computed, ViewChild, ElementRef,
  OnDestroy, OnInit,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/services/auth';
import { CardsService, StagedCardPayload } from '../../core/services/cards';
import { UiService } from '../../core/services/ui';
import { environment } from '../../../environments/environment';

export type ScanState = 'ready' | 'processing' | 'matched' | 'no-match';

export interface SetParallel {
  id: string;
  name: string;
  serial_max: number | null;
  is_auto: boolean;
  color_hex: string | null;
  sort_order: number;
}

export interface ScanResult {
  masterCardId: string | null;
  player: string | null;
  cardNumber: string | null;
  year: string | null;
  releaseName: string | null;
  setName: string | null;
  parallel: { id: string | null; name: string; numberedTo?: number } | null;
  parallelId: string | null;
  parallelName: string;
  grading: { company: string; confidence: string } | null;
  confidence: string;
  setParallels: SetParallel[];
}

export interface StagedCard {
  tempId: string;
  masterCardId: string;
  player: string;
  cardNumber: string | null;
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

  private auth         = inject(AuthService);
  private cardsService = inject(CardsService);
  readonly ui          = inject(UiService);
  private router       = inject(Router);
  private stream: MediaStream | null = null;
  private audioCtx: AudioContext | null = null;

  readonly SPORTS = [
    { label: 'Baseball',   segment: 'baseball' },
    { label: 'Basketball', segment: 'basketball' },
    { label: 'Football',   segment: 'football' },
    { label: 'Hockey',     segment: 'hockey' },
  ];

  scanSport  = signal<string | null>(null);
  scanState  = signal<ScanState>('ready');
  cameraError = signal<string | null>(null);
  scanResult = signal<ScanResult | null>(null);
  scanError  = signal<string | null>(null);

  stagingList      = signal<StagedCard[]>([]);
  stagedCount      = computed(() => this.stagingList().length);
  committing       = signal(false);
  commitError      = signal<string | null>(null);
  commitSuccess    = signal(false);
  showStagingSheet = signal(false);

  async ngOnInit() {
    await this.startCamera();
  }

  ngOnDestroy() {
    this.stopCamera();
  }

  // ── Camera ────────────────────────────────────────────────

  private async startCamera() {
    this.cameraError.set(null);
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
      });
      const video = this.videoEl?.nativeElement;
      if (video) {
        video.srcObject = this.stream;
        await video.play();
        await new Promise<void>(resolve => {
          if (video.videoWidth > 0) { resolve(); return; }
          video.addEventListener('loadedmetadata', () => resolve(), { once: true });
        });
      }
    } catch {
      this.cameraError.set('Camera access denied. Please allow camera permissions and try again.');
    }
  }

  private stopCamera() {
    this.stream?.getTracks().forEach(t => t.stop());
    this.stream = null;
  }

  // ── Capture & Identify ────────────────────────────────────

  async capture() {
    if (this.scanState() !== 'ready') return;
    this.scanState.set('processing');
    this.scanError.set(null);
    this.scanResult.set(null);

    try {
      const blob = this.captureFrameAsBlob();
      const session = await this.auth.getSession();
      const sport = this.scanSport();
      const url = new URL(`${environment.apiUrl}/api/cardsight/identify`);
      if (sport) url.searchParams.set('segment', sport);

      const res = await fetch(url.toString(), {
        method: 'POST',
        headers: {
          'Content-Type': 'image/jpeg',
          Authorization: `Bearer ${session!.access_token}`,
        },
        body: blob,
      });

      if (!res.ok) throw new Error(`Scan failed (${res.status})`);
      const data = await res.json();

      if (!data.success || !data.detections?.length) {
        this.scanError.set('Card not recognized. Try a clearer photo.');
        this.scanState.set('no-match');
        return;
      }

      const best = data.detections[0];
      this.scanResult.set({
        masterCardId:  data.masterCardId ?? null,
        player:        data.masterCardPlayer ?? best.card.name ?? null,
        cardNumber:    data.masterCardNumber ?? best.card.number ?? null,
        year:          best.card.year ?? null,
        releaseName:   best.card.releaseName ?? null,
        setName:       best.card.setName ?? null,
        parallel:      best.card.parallel ? {
          id:        data.parallelId ?? null,
          name:      data.parallelName ?? best.card.parallel.name,
          numberedTo: best.card.parallel.numberedTo,
        } : null,
        parallelId:   data.parallelId ?? null,
        parallelName: data.parallelName ?? 'Base',
        grading:      best.grading ? { company: best.grading.company.name, confidence: best.grading.confidence } : null,
        confidence:   best.confidence,
        setParallels: data.setParallels ?? [],
      });

      this.scanState.set(data.masterCardId ? 'matched' : 'no-match');
      if (data.masterCardId) this.playBeep(800, 0.1);
      else this.playBeep(300, 0.3);
    } catch (e: any) {
      this.scanError.set('Scan failed. Please try again.');
      this.scanState.set('ready');
    }
  }

  private captureFrameAsBlob(): Blob {
    const video = this.videoEl.nativeElement;
    const w = video.videoWidth;
    const h = video.videoHeight;
    if (w < 100 || h < 100) throw new Error('Camera not ready — please wait a moment.');
    const canvas = document.createElement('canvas');
    canvas.width  = w;
    canvas.height = h;
    canvas.getContext('2d')!.drawImage(video, 0, 0);
    const dataUrl = canvas.toDataURL('image/jpeg', 0.85);
    const binary  = atob(dataUrl.split(',')[1]);
    const bytes   = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new Blob([bytes], { type: 'image/jpeg' });
  }

  // ── Staging ───────────────────────────────────────────────

  stageCard(parallelId: string | null, parallelName: string) {
    const result = this.scanResult();
    if (!result?.masterCardId) return;

    this.stagingList.update(list => [{
      tempId:      crypto.randomUUID(),
      masterCardId: result.masterCardId!,
      player:      result.player ?? 'Unknown',
      cardNumber:  result.cardNumber,
      parallelId,
      parallelName,
    }, ...list]);

    this.playBeep(900, 0.08);
    setTimeout(() => {
      this.scanState.set('ready');
      this.scanResult.set(null);
    }, 600);
  }

  stageAsBase() {
    this.stageCard(null, 'Base');
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
      masterCardId: c.masterCardId,
      parallelId:   c.parallelId,
    }));

    const { error } = await this.cardsService.batchAddStagedCards(payloads);

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

  dismiss() {
    this.scanState.set('ready');
    this.scanResult.set(null);
    this.scanError.set(null);
  }

  openManualEntry() {
    const result = this.scanResult();
    this.ui.addCardPrefill.set({ player: result?.player ?? undefined });
    this.ui.addCardOpen.set(true);
  }

  goBack() {
    this.router.navigate(['/collection']);
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
