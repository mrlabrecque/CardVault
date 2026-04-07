import { Injectable, inject } from '@angular/core';
import Fuse from 'fuse.js';
import { AuthService } from './auth';
import { MasterCard } from './cards';
import { SetRecord as ChecklistRecord } from './releases';

export interface ParsedCard {
  rawText: string;
  playerCandidates: string[];
  cardNumber: string | null;
  numberPrefix: string | null;   // e.g. "F-" for Fireworks insert
  year: number | null;
  brand: string | null;
}

@Injectable({ providedIn: 'root' })
export class ScannerService {
  private auth = inject(AuthService);

  private fuseIndex: Fuse<MasterCard> | null = null;
  private indexedChecklistId: string | null = null;

  // ── OCR ─────────────────────────────────────────────────

  /**
   * Run Tesseract OCR on an image data URL.
   * Dynamically imports tesseract.js to avoid bundling it in the main chunk.
   */
  async recognize(imageDataUrl: string): Promise<string> {
    const Tesseract = await import('tesseract.js');
    const result = await Tesseract.default.recognize(imageDataUrl, 'eng');
    return result.data.text;
  }

  // ── Text Parsing ─────────────────────────────────────────

  parseCardText(text: string): ParsedCard {
    return {
      rawText: text,
      playerCandidates: this.extractPlayerCandidates(text),
      cardNumber:       this.extractCardNumber(text)?.number ?? null,
      numberPrefix:     this.extractCardNumber(text)?.prefix ?? null,
      year:             this.extractSetInfo(text).year,
      brand:            this.extractSetInfo(text).brand,
    };
  }

  /**
   * Match a card number's prefix against available checklists.
   * e.g. "F-12" with prefix "F-" matches the Fireworks checklist.
   * Returns the base checklist if no prefix matches (null prefix = base set).
   */
  matchChecklistFromPrefix(
    prefix: string | null,
    checklists: ChecklistRecord[]
  ): ChecklistRecord | null {
    if (!prefix) {
      return checklists.find(c => c.prefix === null) ?? checklists[0] ?? null;
    }
    const normalized = prefix.toUpperCase();
    return (
      checklists.find(c => c.prefix?.toUpperCase() === normalized) ??
      checklists.find(c => c.prefix === null) ??
      checklists[0] ??
      null
    );
  }

  // ── Fuzzy Matching ────────────────────────────────────────

  /**
   * Build (or rebuild) the Fuse index for a checklist.
   * No-op if the same checklist is already indexed.
   */
  buildIndex(checklistId: string, cards: MasterCard[]): void {
    if (this.indexedChecklistId === checklistId) return;
    this.fuseIndex = new Fuse(cards, {
      keys: ['player'],
      threshold: 0.4,       // allows ~2 character OCR errors
      minMatchCharLength: 3,
      includeScore: true,
    });
    this.indexedChecklistId = checklistId;
  }

  /**
   * Run player name candidates through the Fuse index.
   * Returns up to 5 best matches, ordered by score.
   */
  fuzzyMatch(candidates: string[]): MasterCard[] {
    if (!this.fuseIndex || candidates.length === 0) return [];

    const seen = new Set<string>();
    const results: Array<{ item: MasterCard; score: number }> = [];

    for (const candidate of candidates) {
      const matches = this.fuseIndex.search(candidate);
      for (const m of matches) {
        if (!seen.has(m.item.id)) {
          seen.add(m.item.id);
          results.push({ item: m.item, score: m.score ?? 1 });
        }
      }
    }

    return results
      .sort((a, b) => a.score - b.score)
      .slice(0, 5)
      .map(r => r.item);
  }

  clearIndex(): void {
    this.fuseIndex = null;
    this.indexedChecklistId = null;
  }

  // ── Pending Set Submission ────────────────────────────────

  async submitPendingSet(data: {
    name: string;
    year: number;
    sport: string;
    release_type: string;
  }): Promise<void> {
    const { data: { user } } = await this.auth.getClient().auth.getUser();
    await this.auth.getClient()
      .from('pending_sets')
      .upsert(
        { ...data, submitted_by: user?.id ?? null, submission_count: 1 },
        { onConflict: 'name,year,sport', ignoreDuplicates: false }
      );
  }

  // ── Private Parsing Helpers ───────────────────────────────

  private extractCardNumber(text: string): { number: string; prefix: string | null } | null {
    // Matches: F-12, F-298, M-45 (insert prefix), or plain 298, 12, etc.
    // Also handles "298/300" style (numbered cards)
    const prefixedMatch = text.match(/\b([A-Z]{1,3})-(\d{1,4})\b/);
    if (prefixedMatch) {
      return { prefix: `${prefixedMatch[1]}-`, number: prefixedMatch[2] };
    }

    // Look for standalone number: "#298" or "No. 298" or just "298" near end of line
    const plainMatch = text.match(/(?:#|No\.?\s*)(\d{1,4})(?:\/\d+)?/i);
    if (plainMatch) {
      return { prefix: null, number: plainMatch[1] };
    }

    return null;
  }

  private extractSetInfo(text: string): { year: number | null; brand: string | null } {
    // © 2026 Panini America  |  ©2026 Topps  |  Copyright 2026 Upper Deck
    const match = text.match(/(?:©|Copyright)\s*(\d{4})\s+([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+)?)/);
    if (match) {
      return {
        year: parseInt(match[1], 10),
        brand: match[2].trim(),
      };
    }
    return { year: null, brand: null };
  }

  private extractPlayerCandidates(text: string): string[] {
    const candidates: string[] = [];
    const lines = text.split('\n').map(l => l.trim()).filter(l => l.length > 2);

    for (const line of lines) {
      // All-uppercase line of 4–40 chars — common card back header format
      if (/^[A-Z][A-Z\s\-'\.]{3,39}$/.test(line) && !this.looksLikeJunk(line)) {
        candidates.push(line.trim());
      }
      // Title-case two-word+ name pattern: "Victor Wembanyama", "LeBron James"
      const titleMatch = line.match(/^([A-Z][a-z']+(?:\s+[A-Z][a-z']+){1,3})$/);
      if (titleMatch && !this.looksLikeJunk(titleMatch[1])) {
        candidates.push(titleMatch[1]);
      }
    }

    // Deduplicate while preserving order
    return [...new Set(candidates)];
  }

  private looksLikeJunk(s: string): boolean {
    // Filter out common non-name strings that appear on card backs
    const junkPatterns = [
      /^\d/,                        // starts with number
      /^(NBA|NFL|MLB|MLS|NHL)/,     // league acronyms
      /PANINI|TOPPS|UPPER DECK|DONRUSS|FLEER|BOWMAN/i,
      /BASKETBALL|BASEBALL|FOOTBALL|SOCCER/i,
      /ROOKIE|AUTOGRAPH|MEMORABILIA/i,
      /SERIAL|NUMBERED|LIMITED/i,
    ];
    return junkPatterns.some(r => r.test(s));
  }
}
