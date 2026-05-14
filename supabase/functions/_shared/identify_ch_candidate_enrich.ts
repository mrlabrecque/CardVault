/**
 * Batch-enrich CardHedge image-search candidate rows for `identify-card`:
 * guide prices from `card-details`, optional CardSight spine fields (see ch_set_to_cardsight_spine).
 */
import {
  enrichChCandidatesWithSpine,
  type ChCandidateJson,
  type EnrichSpineContext,
} from './ch_set_to_cardsight_spine.ts';
import { hydratePersistFieldsFromCardHedgeCardId } from './cardhedge_hydrate_variant.ts';
import { normalizePriceEntry } from './cardhedge_persist_master.ts';

export async function batchEnrichChCandidatesWithPrices(
  apiKey: string,
  candidates: ChCandidateJson[],
  opts?: { concurrency?: number; perCardTimeoutMs?: number },
): Promise<void> {
  const conc = Math.min(8, Math.max(1, opts?.concurrency ?? 4));
  const timeout = opts?.perCardTimeoutMs ?? 12_000;
  for (let start = 0; start < candidates.length; start += conc) {
    const chunk = candidates.slice(start, start + conc);
    await Promise.all(
      chunk.map(async (row) => {
        const id = String(row.card_id ?? '').trim();
        if (!id) return;
        const h = await hydratePersistFieldsFromCardHedgeCardId(apiKey, id, { timeoutMs: timeout });
        const out: { grade: string; price: number }[] = [];
        if (Array.isArray(h.prices)) {
          for (const p of h.prices) {
            const n = normalizePriceEntry(p);
            if (n) out.push(n);
          }
        }
        row.prices = out.slice(0, 24);
        const img = h.imageUrl;
        if (typeof img === 'string' && img.trim() && (!row.image || String(row.image).trim() === '')) {
          row.image = img.trim();
        }
      }),
    );
  }
}

export async function enrichChCandidatesFull(
  ctx: EnrichSpineContext,
  candidates: ChCandidateJson[],
  opts?: { priceConcurrency?: number; perCardTimeoutMs?: number },
): Promise<void> {
  if (ctx.cardHedgeApiKey) {
    await batchEnrichChCandidatesWithPrices(ctx.cardHedgeApiKey, candidates, {
      concurrency: opts?.priceConcurrency ?? 4,
      perCardTimeoutMs: opts?.perCardTimeoutMs ?? 12_000,
    });
  }
  await enrichChCandidatesWithSpine(ctx, candidates);
}
