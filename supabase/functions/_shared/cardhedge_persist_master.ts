/**
 * Writes guide-price data to `master_card_definitions` + `current_prices` (shared by
 * `cardhedge-persist-variant` and `cardhedge-search-cards` when persisting inline).
 */
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

export type PersistGuidePricesInput = {
  masterVariantId: string;
  guidePriceCardId?: string;
  imageUrl?: string | null;
  prices?: unknown[];
  sales7d?: unknown;
  sales30d?: unknown;
  gain?: unknown;
};

export type CatalogMasterSnapshot = {
  id: string;
  player: string;
  card_number: string | null;
  is_rookie: boolean;
  is_auto: boolean;
  is_patch: boolean;
  is_ssp: boolean;
  serial_max: number | null;
  image_url: string | null;
  cardhedge_id: string | null;
  gain: number | null;
};

function toFiniteNumber(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const n = parseFloat(v.replace(/[^0-9.-]/g, ''));
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/** Exported for card-search: detect whether upstream already sent persistable rows. */
export function normalizePriceEntry(p: unknown): { grade: string; price: number } | null {
  if (!p || typeof p !== 'object') return null;
  const o = p as Record<string, unknown>;
  const gradeRaw =
    o.grade ?? o.Grade ?? o.label ?? o.Label ?? o.name ?? o.Name ?? o.slab ?? o.Slab;
  const grade = String(gradeRaw ?? '').trim();
  const priceRaw = o.price ?? o.Price ?? o.value ?? o.Value ?? o.avg ?? o.Avg ?? o.median ?? o.Median;
  const price = toFiniteNumber(priceRaw);
  if (!grade || price === null || price <= 0) return null;
  return { grade, price };
}

/** Upload upstream image to Storage, patch master, replace `current_prices`. */
export async function persistGuidePricesOntoMaster(
  admin: SupabaseClient,
  input: PersistGuidePricesInput,
): Promise<{ storedImageUrl: string | null }> {
  const masterVariantId = input.masterVariantId.trim();
  if (!masterVariantId) return { storedImageUrl: null };

  const { data: row, error: qErr } = await admin
    .from('master_card_definitions')
    .select('id')
    .eq('id', masterVariantId)
    .maybeSingle();

  if (qErr || !row) return { storedImageUrl: null };

  let storedImageUrl: string | null = null;
  const upstreamImage = typeof input.imageUrl === 'string' ? input.imageUrl.trim() : '';
  if (upstreamImage.length > 0 && upstreamImage.startsWith('http')) {
    try {
      const imgRes = await fetch(upstreamImage);
      if (imgRes.ok) {
        const buf = await imgRes.arrayBuffer();
        const path = `cardhedge/${masterVariantId}.jpg`;
        const { error: upErr } = await admin.storage.from('card-images').upload(path, buf, {
          contentType: 'image/jpeg',
          upsert: true,
        });
        if (!upErr) {
          const { data: pub } = admin.storage.from('card-images').getPublicUrl(path);
          storedImageUrl = pub.publicUrl;
        }
      }
    } catch (_e) {
      // ignore image failures
    }
  }

  const patch: Record<string, unknown> = {
    cardhedge_fetched_at: new Date().toISOString(),
  };
  if (input.guidePriceCardId) patch.cardhedge_id = input.guidePriceCardId;
  if (storedImageUrl) patch.image_url = storedImageUrl;

  const s7 = toFiniteNumber(input.sales7d);
  const s30 = toFiniteNumber(input.sales30d);
  const gn = toFiniteNumber(input.gain);
  if (s7 !== null) patch.sales_7d = s7;
  if (s30 !== null) patch.sales_30d = s30;
  if (gn !== null) patch.gain = gn;

  const { error: updErr } = await admin.from('master_card_definitions').update(patch).eq('id', masterVariantId);
  if (updErr) console.error('[guide_persist_master] master update', updErr);

  if (Array.isArray(input.prices) && input.prices.length > 0) {
    await admin.from('current_prices').delete().eq('master_card_id', masterVariantId);
    const rows = input.prices
      .map((p) => {
        const norm = normalizePriceEntry(p);
        if (!norm) return null;
        return {
          master_card_id: masterVariantId,
          grade: norm.grade,
          price: norm.price,
          fetched_at: new Date().toISOString(),
        };
      })
      .filter(Boolean) as Record<string, unknown>[];

    if (rows.length > 0) {
      const { error: insErr } = await admin.from('current_prices').insert(rows);
      if (insErr) console.error('[guide_persist_master] current_prices insert', insErr);
    }
  }

  return { storedImageUrl };
}

/** Same coalesce as Flutter `fetchMasterCardById` / SQL view for catalog hero. */
export async function fetchCatalogMasterSnapshot(
  admin: SupabaseClient,
  masterVariantId: string,
): Promise<CatalogMasterSnapshot | null> {
  const { data, error } = await admin
    .from('master_card_definitions')
    .select(
      'id, is_auto, is_patch, is_ssp, serial_max, image_url, cardhedge_id, gain, set_cards(player, card_number, is_rookie, image_url)',
    )
    .eq('id', masterVariantId.trim())
    .maybeSingle();

  if (error || !data) return null;
  const map = data as Record<string, unknown>;
  const scRaw = map['set_cards'];
  const sc = scRaw && typeof scRaw === 'object' ? (scRaw as Record<string, unknown>) : null;
  const masterImg = typeof map['image_url'] === 'string' ? map['image_url'].trim() : '';
  const checklistImg = typeof sc?.['image_url'] === 'string' ? (sc['image_url'] as string).trim() : '';
  const coalesced =
    masterImg.length > 0 ? masterImg : checklistImg.length > 0 ? checklistImg : null;

  const chId = typeof map['cardhedge_id'] === 'string' ? (map['cardhedge_id'] as string).trim() : '';
  const gainRaw = map['gain'];
  const gain =
    typeof gainRaw === 'number' && Number.isFinite(gainRaw)
      ? gainRaw
      : typeof gainRaw === 'string'
      ? (() => {
          const n = parseFloat((gainRaw as string).replace(/[^0-9.-]/g, ''));
          return Number.isFinite(n) ? n : null;
        })()
      : null;
  return {
    id: String(map['id']),
    player: typeof sc?.['player'] === 'string' ? sc['player'] : '',
    card_number: typeof sc?.['card_number'] === 'string' ? (sc['card_number'] as string) : null,
    is_rookie: Boolean(sc?.['is_rookie']),
    is_auto: Boolean(map['is_auto']),
    is_patch: Boolean(map['is_patch']),
    is_ssp: Boolean(map['is_ssp']),
    serial_max: typeof map['serial_max'] === 'number' ? map['serial_max'] as number : null,
    image_url: coalesced,
    cardhedge_id: chId.length > 0 ? chId : null,
    gain,
  };
}
