/**
 * CardSight set parallels → `set_parallels` upsert.
 * Shared by catalog-lazy-import and catalog-import-cards.
 */

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { cardsightFetch } from './cardsight_fetch.ts';

const CARDSIGHT_BASE = 'https://api.cardsight.ai';

export type CardsightParallel = { id: string; name: string; numberedTo?: number };

export type SetParallelRow = {
  id: string;
  name: string;
  sort_order: number | null;
};

/** Prefer `Base`, else lowest sort_order / name. */
export function pickBaseParallelId(
  rows: { id: string; name: string; sort_order: number | null }[],
): string | null {
  if (!rows.length) return null;
  const sorted = [...rows].sort((a, b) => {
    const ab = a.name.trim().toLowerCase() === 'base' ? 0 : 1;
    const bb = b.name.trim().toLowerCase() === 'base' ? 0 : 1;
    if (ab !== bb) return ab - bb;
    const sa = a.sort_order ?? 999999;
    const sb = b.sort_order ?? 999999;
    if (sa !== sb) return sa - sb;
    return a.name.localeCompare(b.name);
  });
  return sorted[0]?.id ?? null;
}

/** Deduplicate by name while keeping the richest numberedTo payload. */
export function dedupeCardsightParallels(
  raw: CardsightParallel[],
): CardsightParallel[] {
  const parallelsByName = new Map<string, CardsightParallel>();
  for (const p of raw) {
    const existing = parallelsByName.get(p.name);
    if (!existing) {
      parallelsByName.set(p.name, p);
      continue;
    }
    const existingHasNumbered = existing.numberedTo != null;
    const candidateHasNumbered = p.numberedTo != null;
    if (!existingHasNumbered && candidateHasNumbered) {
      parallelsByName.set(p.name, p);
    }
  }
  return Array.from(parallelsByName.values());
}

function serialMaxFromParallelName(name: string): number | null {
  const m = name.match(/\/\s*(\d{1,4})\b/);
  if (!m) return null;
  const n = Number.parseInt(m[1], 10);
  return Number.isFinite(n) ? n : null;
}

export function parallelUpsertRows(
  setId: string,
  parallels: CardsightParallel[],
): Array<{
  set_id: string;
  name: string;
  serial_max: number | null;
  is_auto: boolean;
  color_hex: null;
  sort_order: number;
  cardsight_id: string;
}> {
  return parallels.map((p, i) => ({
    set_id: setId,
    name: p.name,
    serial_max: p.numberedTo ?? serialMaxFromParallelName(p.name) ?? null,
    is_auto: /\bauto(graph)?\b/i.test(p.name),
    color_hex: null,
    sort_order: i,
    cardsight_id: p.id,
  }));
}

export async function fetchCardsightSetParallels(
  apiKey: string,
  cardsightSetId: string,
): Promise<CardsightParallel[]> {
  const setRes = await cardsightFetch(
    `${CARDSIGHT_BASE}/v1/catalog/sets/${cardsightSetId}`,
    apiKey,
  );
  const setDetail = await setRes.json() as {
    parallels?: CardsightParallel[];
  };
  return dedupeCardsightParallels(setDetail.parallels ?? []);
}

async function selectParallelsForSet(
  supabase: SupabaseClient,
  setId: string,
): Promise<SetParallelRow[]> {
  const { data, error } = await supabase
    .from('set_parallels')
    .select('id, name, sort_order')
    .eq('set_id', setId);
  if (error) throw new Error(error.message);
  return (data ?? []) as SetParallelRow[];
}

/** Upsert CardSight parallels for a vault set. Returns DB rows (id, name, sort_order). */
export async function upsertParallelsFromCardsight(
  supabase: SupabaseClient,
  setId: string,
  parallels: CardsightParallel[],
): Promise<SetParallelRow[]> {
  if (parallels.length === 0) return selectParallelsForSet(supabase, setId);

  const rows = parallelUpsertRows(setId, parallels);
  const { error } = await supabase
    .from('set_parallels')
    .upsert(rows, { onConflict: 'set_id,name' });
  if (error) throw new Error(error.message);

  return selectParallelsForSet(supabase, setId);
}

/** Insert a synthetic Base row when CardSight returns no parallels. */
export async function ensureBaseParallelRow(
  supabase: SupabaseClient,
  setId: string,
): Promise<SetParallelRow[]> {
  const { error } = await supabase
    .from('set_parallels')
    .upsert(
      {
        set_id: setId,
        name: 'Base',
        serial_max: null,
        is_auto: false,
        color_hex: null,
        sort_order: 0,
        cardsight_id: null,
      },
      { onConflict: 'set_id,name' },
    );
  if (error) throw new Error(error.message);
  return selectParallelsForSet(supabase, setId);
}

/**
 * Returns parallels for [setId], importing from CardSight when the set has none yet.
 */
export async function ensureSetParallelsFromCardsight(
  supabase: SupabaseClient,
  apiKey: string,
  setId: string,
  cardsightSetId: string,
): Promise<{ rows: SetParallelRow[]; importedFromCardsight: boolean }> {
  let rows = await selectParallelsForSet(supabase, setId);
  if (rows.length > 0) {
    return { rows, importedFromCardsight: false };
  }

  const csParallels = await fetchCardsightSetParallels(apiKey, cardsightSetId);
  if (csParallels.length > 0) {
    rows = await upsertParallelsFromCardsight(supabase, setId, csParallels);
  } else {
    rows = await ensureBaseParallelRow(supabase, setId);
  }

  return { rows, importedFromCardsight: true };
}

const HYDRATE_PARALLEL_DELAY_MS = 150;

/**
 * Always refresh `set_parallels` from CardSight set detail (idempotent upsert).
 * Returns number of parallel definitions written (or 1 for synthetic Base).
 */
export async function hydrateSetParallelsFromCardsight(
  supabase: SupabaseClient,
  apiKey: string,
  setId: string,
  cardsightSetId: string,
): Promise<number> {
  const csParallels = await fetchCardsightSetParallels(apiKey, cardsightSetId);
  if (csParallels.length > 0) {
    await upsertParallelsFromCardsight(supabase, setId, csParallels);
    return csParallels.length;
  }
  await ensureBaseParallelRow(supabase, setId);
  return 1;
}

export { HYDRATE_PARALLEL_DELAY_MS };
