import { Component, inject, signal, OnInit } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SetsService, SetRecord, ChecklistRecord } from '../../../core/services/sets';

@Component({
  selector: 'app-checklist-manager',
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './checklist-manager.html',
})
export class ChecklistManager implements OnInit {
  private route = inject(ActivatedRoute);
  private setsService = inject(SetsService);

  readonly setId = this.route.snapshot.paramMap.get('setId')!;

  set = signal<SetRecord | null>(null);
  checklists = signal<ChecklistRecord[]>([]);
  deleting = signal<string | null>(null);
  saving = signal(false);
  saveError = signal('');

  // New checklist form
  newName = '';
  newPrefix = '';

  ngOnInit() {
    this.loadSet();
    this.loadChecklists();
  }

  private async loadSet() {
    const sets = await this.setsService.getSets();
    this.set.set(sets.find(s => s.id === this.setId) ?? null);
  }

  private async loadChecklists() {
    this.checklists.set(await this.setsService.getChecklists(this.setId));
  }

  async add() {
    const name = this.newName.trim();
    if (!name) return;
    this.saving.set(true);
    this.saveError.set('');
    const prefix = this.newPrefix.trim() || null;
    const { error } = await this.setsService.createChecklist(this.setId, name, prefix);
    this.saving.set(false);
    if (error) {
      this.saveError.set((error as any).message ?? 'Failed to save.');
    } else {
      this.newName = '';
      this.newPrefix = '';
      await this.loadChecklists();
    }
  }

  async remove(id: string) {
    this.deleting.set(id);
    await this.setsService.deleteChecklist(id);
    this.deleting.set(null);
    await this.loadChecklists();
  }
}
