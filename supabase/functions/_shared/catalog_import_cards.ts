/**
 * CardSight release/set card checklist → `set_cards` + base `master_card_definitions`.
 * Images are optional (cron / lazy fetch).
 */

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { cardsightFetch } from './cardsight_fetch.ts';
import { pickBaseParallelId, type SetParallelRow } from './catalog_set_parallels.ts';

export const CARDSIGHT_CATALOG_BASE = 'https://api.cardsight.ai';
export const CARDSIGHT_CARDS_PAGE_SIZE = 100;
export const CARDSIGHT_CARDS_PAGE_DELAY_MS = 250;

export type CardsightCatalogCard = {
  id: string;
  number: string;
  name: string;
  attributes?: string[];
  isParallelOnly?: boolean;
  setId?: string;
};

export type MergedCatalogCard = {
  player: string;
  cardNumber: string;
  isRookie: boolean;
  isAuto: boolean;
  isPatch: boolean;
  isSSP: boolean;
  cardsightCardId: string;
};

export function mergeCardsIntoMap(
  cards: CardsightCatalogCard[],
  cardMap: Map<string, MergedCatalogCard>,
): void {
  for (const card of cards) {
    if (card.isParallelOnly) continue;
    if (!card.name?.trim()) continue;

    const attrs = (card.attributes ?? []).map((a) => a.toUpperCase());
    const key = `${card.name.trim()}|${card.number ?? ''}`;
    const existing = cardMap.get(key);

    if (existing) {
      existing.isRookie = existing.isRookie || attrs.includes('RC');
      existing.isAuto = existing.isAuto || attrs.includes('AU');
      existing.isPatch = existing.isPatch || attrs.includes('GU');
      existing.isSSP = existing.isSSP || attrs.includes('SSP');
    } else {
      cardMap.set(key, {
        player: card.name.trim(),
        cardNumber: card.number ?? '',
        isRookie: attrs.includes('RC'),
        isAuto: attrs.includes('AU'),
        isPatch: attrs.includes('GU'),
        isSSP: attrs.includes('SSP'),
        cardsightCardId: card.id,
      });
    }
  }
}

/** Paginated `GET /v1/catalog/releases/{releaseId}/cards` (optional `setId` filter). */
export async function fetchAllCardsightReleaseCards(
  apiKey: string,
  cardsightReleaseId: string,
  options: { cardsightSetId?: string } = {},
): Promise<CardsightCatalogCard[]> {
  const all: CardsightCatalogCard[] = [];
  let page = 0;
  let hasMore = true;

  while (hasMore) {
    const url = new URL(
      `${CARDSIGHT_CATALOG_BASE}/v1/catalog/releases/${cardsightReleaseId}/cards`,
    );
    url.searchParams.set('take', String(CARDSIGHT_CARDS_PAGE_SIZE));
    url.searchParams.set('skip', String(page * CARDSIGHT_CARDS_PAGE_SIZE));
    if (options.cardsightSetId) {
      url.searchParams.set('setId', options.cardsightSetId);
    }

    const csRes = await cardsightFetch(url, apiKey);
    const csData = await csRes.json() as {
      cards?: CardsightCatalogCard[];
      total_count?: number;
    };
    const batch = csData.cards ?? [];
    if (batch.length === 0) {
      hasMore = false;
    } else {
      all.push(...batch);
      hasMore = batch.length === CARDSIGHT_CARDS_PAGE_SIZE;
      page++;
    }

    if (hasMore) {
      await new Promise((r) => setTimeout(r, CARDSIGHT_CARDS_PAGE_DELAY_MS));
    }
  }

  return all;
}

export function groupCardsByCardsightSetId(
  cards: CardsightCatalogCard[],
): Map<string, CardsightCatalogCard[]> {
  const bySet = new Map<string, CardsightCatalogCard[]>();
  for (const card of cards) {
    const sid = card.setId?.trim();
    if (!sid) continue;
    const list = bySet.get(sid) ?? [];
    list.push(card);
    bySet.set(sid, list);
  }
  return bySet;
}

/** Upsert checklist rows for one vault set (no images). */
export async function upsertVaultSetCards(
  supabase: SupabaseClient,
  dbSetId: string,
  baseParallelId: string,
  rawCards: CardsightCatalogCard[],
): Promise<{ imported: number; merged: number }> {
  const cardMap = new Map<string, MergedCatalogCard>();
  mergeCardsIntoMap(rawCards, cardMap);

  if (cardMap.size === 0) {
    return { imported: 0, merged: 0 };
  }

  const setRows = Array.from(cardMap.values()).map((card) => ({
    set_id: dbSetId,
    player: card.player,
    card_number: card.cardNumber || null,
    is_rookie: card.isRookie,
    image_url: null,
    cardsight_card_id: card.cardsightCardId,
  }));

  const { data: upsertedSetCards, error: setErr } = await supabase
    .from('set_cards')
    .upsert(setRows, { onConflict: 'cardsight_card_id' })
    .select('id, cardsight_card_id');

  if (setErr) throw new Error(setErr.message);

  const byCsId = new Map(
    (upsertedSetCards ?? []).map((r: { id: string; cardsight_card_id: string }) =>
      [r.cardsight_card_id, r.id] as const
    ),
  );

  const variantRows = Array.from(cardMap.values()).map((card) => {
    const setCardId = byCsId.get(card.cardsightCardId);
    if (!setCardId) return null;
    return {
      set_card_id: setCardId,
      parallel_id: baseParallelId,
      is_auto: card.isAuto,
      is_patch: card.isPatch,
      is_ssp: card.isSSP,
      serial_max: null as number | null,
    };
  }).filter(Boolean) as {
    set_card_id: string;
    parallel_id: string;
    is_auto: boolean;
    is_patch: boolean;
    is_ssp: boolean;
    serial_max: number | null;
  }[];

  const { error: varErr } = await supabase
    .from('master_card_definitions')
    .upsert(variantRows, { onConflict: 'set_card_id,parallel_id' });

  if (varErr) throw new Error(varErr.message);

  return {
    imported: upsertedSetCards?.length ?? 0,
    merged: cardMap.size,
  };
}

export function resolveBaseParallelId(parallelRows: SetParallelRow[]): string {
  const id = pickBaseParallelId(parallelRows);
  if (!id) throw new Error('Could not resolve a base parallel for this set');
  return id;
}
