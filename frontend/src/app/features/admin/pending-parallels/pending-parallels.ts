import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { MessageService } from 'primeng/api';
import { Toast } from 'primeng/toast';
import { ReleasesService, PendingParallel } from '../../../core/services/releases';

interface PromoteState {
  serial_max: number | null;
  is_auto: boolean;
  color_hex: string | null;
}

@Component({
  selector: 'app-pending-parallels',
  imports: [CommonModule, FormsModule, RouterLink, Toast],
  providers: [MessageService],
  templateUrl: './pending-parallels.html',
  styleUrl: './pending-parallels.scss',
})
export class PendingParallels implements OnInit {
  private releasesService = inject(ReleasesService);
  private messageService = inject(MessageService);

  items = signal<PendingParallel[]>([]);
  loading = signal(true);
  // Map of pending id → promote form state (null = not expanded)
  promoteMap = signal<Record<string, PromoteState | null>>({});
  working = signal<string | null>(null);

  ngOnInit() {
    this.load();
  }

  private async load() {
    this.loading.set(true);
    this.items.set(await this.releasesService.getPendingParallels());
    this.loading.set(false);
  }

  releaseName(item: PendingParallel): string {
    const r = item.sets?.releases;
    return r ? `${r.year} ${r.name}` : item.set_id;
  }

  sportIcon(item: PendingParallel): string {
    const map: Record<string, string> = {
      Basketball: '🏀', Baseball: '⚾', Football: '🏈', Soccer: '⚽',
    };
    return map[item.sets?.releases?.sport ?? ''] ?? '🃏';
  }

  togglePromote(item: PendingParallel) {
    const current = this.promoteMap()[item.id];
    this.promoteMap.update(m => ({
      ...m,
      [item.id]: current ? null : { serial_max: null, is_auto: false, color_hex: null },
    }));
  }

  promoteState(item: PendingParallel): PromoteState | null {
    return this.promoteMap()[item.id] ?? null;
  }

  async approve(item: PendingParallel) {
    const state = this.promoteState(item);
    if (!state) return;
    this.working.set(item.id);
    const { error } = await this.releasesService.approveParallel(item, state) as any;
    this.working.set(null);
    if (error) {
      this.messageService.add({ severity: 'error', summary: 'Error', detail: error.message });
    } else {
      this.messageService.add({ severity: 'success', summary: 'Promoted', detail: `"${item.name}" added to parallels.` });
      await this.load();
    }
  }

  async dismiss(item: PendingParallel) {
    this.working.set(item.id);
    await this.releasesService.dismissParallel(item.id);
    this.working.set(null);
    await this.load();
  }
}
