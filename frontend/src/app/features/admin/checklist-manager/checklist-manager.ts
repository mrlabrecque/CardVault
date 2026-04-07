import { Component, inject, signal, OnInit } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ReleasesService, ReleaseRecord, SetRecord } from '../../../core/services/releases';

@Component({
  selector: 'app-set-manager',
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './checklist-manager.html',
})
export class SetManager implements OnInit {
  private route = inject(ActivatedRoute);
  private releasesService = inject(ReleasesService);

  readonly releaseId = this.route.snapshot.paramMap.get('releaseId')!;

  release = signal<ReleaseRecord | null>(null);
  sets = signal<SetRecord[]>([]);
  deleting = signal<string | null>(null);
  saving = signal(false);
  saveError = signal('');

  // New set form
  newName = '';
  newPrefix = '';

  ngOnInit() {
    this.loadRelease();
    this.loadSets();
  }

  private async loadRelease() {
    const releases = await this.releasesService.getReleases();
    this.release.set(releases.find(r => r.id === this.releaseId) ?? null);
  }

  private async loadSets() {
    this.sets.set(await this.releasesService.getSets(this.releaseId));
  }

  async add() {
    const name = this.newName.trim();
    if (!name) return;
    this.saving.set(true);
    this.saveError.set('');
    const prefix = this.newPrefix.trim() || null;
    const { error } = await this.releasesService.createSet(this.releaseId, name, prefix);
    this.saving.set(false);
    if (error) {
      this.saveError.set((error as any).message ?? 'Failed to save.');
    } else {
      this.newName = '';
      this.newPrefix = '';
      await this.loadSets();
    }
  }

  async remove(id: string) {
    this.deleting.set(id);
    await this.releasesService.deleteSet(id);
    this.deleting.set(null);
    await this.loadSets();
  }
}
