/**
 * One-shot: lazy-import CardSight spine, import checklist cards, ensure parallel + variant row,
 * optionally persist CardHedge guide prices. Auth: user JWT.
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { hydratePersistFieldsFromCardHedgeCardId } from '../_shared/cardhedge_hydrate_variant.ts';
import { persistGuidePricesOntoMaster } from '../_shared/cardhedge_persist_master.ts';
import { verifyUserJwt } from '../_shared/supabase_user_jwt.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

async function invokeEdge(fn: string, body: unknown): Promise<Record<string, unknown>> {
  const base = Deno.env.get('SUPABASE_URL')!.replace(/\/$/, '');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const res = await fetch(`${base}/functions/v1/${fn}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${key}`,
      apikey: key,
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(text) as Record<string, unknown>;
  } catch {
    throw new Error(`Edge ${fn}: ${text.slice(0, 240)}`);
  }
  if (!res.ok || data.error) {
    throw new Error(String(data.error ?? `HTTP ${res.status}`));
  }
  return data;
}

function normParallelName(s: string): string {
  return s.toLowerCase().replace(/\s+/g, ' ').trim();
}

/** Normalized names that mean the paper / default parallel when user intent is "Base". */
const BASE_PARALLEL_SYNONYMS = new Set([
  'base',
  'base set',
  'base parallel',
  'base card',
  'baseset',
  'baseparallel',
]);

/**
 * Resolves `set_parallels.id` for a display name. For intent "Base", never uses substring
 * matching — `pn.includes("base")` false-positives on "Baseball", "Database", etc.
 */
function resolveParallelId(
  rows: { id: string; name: string; serial_max: number | null; is_auto: boolean; sort_order: number | null }[],
  parallelName: string,
): string | null {
  const rowsSorted = [...rows].sort(
    (a, b) => (a.sort_order ?? 999999) - (b.sort_order ?? 999999) || a.name.localeCompare(b.name),
  );
  const target = normParallelName(parallelName);
  if (!target) return null;

  for (const p of rowsSorted) {
    if (normParallelName(p.name) === target) return p.id;
  }

  if (target === 'base') {
    for (const p of rowsSorted) {
      const pn = normParallelName(p.name);
      if (BASE_PARALLEL_SYNONYMS.has(pn)) return p.id;
    }
    // No row named Base / Base Set — same rule as Postgres `_default_parallel_for_set`,
    // `set_card_base_variants`, and `catalog-import-cards` pickBaseParallelId: use the
    // parallel with lowest sort_order (rowsSorted[0] after sort).
    return rowsSorted[0]?.id ?? null;
  }

  for (const p of rowsSorted) {
    const pn = normParallelName(p.name);
    if (pn.includes(target) || target.includes(pn)) return p.id;
  }
  return null;
}

function serialMaxFromParallelName(name: string): number | null {
  const m = name.match(/\/\s*(\d{1,5})\b/);
  if (!m) return null;
  const n = parseInt(m[1]!, 10);
  return Number.isFinite(n) ? n : null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Unauthorized' }, 401);
  const _verifiedUserId = await verifyUserJwt(authHeader, supabaseUrl);
  if (!_verifiedUserId) return json({ error: 'Unauthorized' }, 401);

  const admin = createClient(supabaseUrl, serviceKey);

  let body: {
    cardsightReleaseId: string;
    cardsightSetId: string;
    cardsightCardId: string;
    releaseName: string;
    releaseYear: number;
    releaseSegmentId?: string;
    cardHedgeCardId?: string;
    cardHedgeVariant?: string;
    parallelName?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const cr = String(body.cardsightReleaseId ?? '').trim();
  const cs = String(body.cardsightSetId ?? '').trim();
  const cc = String(body.cardsightCardId ?? '').trim();
  const releaseName = String(body.releaseName ?? '').trim() || 'Unknown Release';
  const releaseYear = Number.isFinite(body.releaseYear) ? Math.trunc(body.releaseYear as number) : new Date().getFullYear();
  const segment = String(body.releaseSegmentId ?? '').trim();
  const chId = String(body.cardHedgeCardId ?? '').trim();
  const variantRaw = String(body.parallelName ?? body.cardHedgeVariant ?? '').trim();

  if (!cr || !cs || !cc) {
    return json({ error: 'cardsightReleaseId, cardsightSetId, and cardsightCardId are required' }, 400);
  }

  try {
    const lazy = await invokeEdge('catalog-lazy-import', {
      cardsightReleaseId: cr,
      releaseName,
      releaseYear: String(releaseYear),
      releaseSegmentId: segment,
      cardsightSetId: cs,
    });
    const vaultSetId = String(lazy.setId ?? '').trim();
    if (!vaultSetId) throw new Error('lazy import returned no setId');

    await invokeEdge('catalog-import-cards', {
      cardsightReleaseId: cr,
      cardsightSetId: cs,
      setId: vaultSetId,
    });

    let parallelName = variantRaw;
    if (!parallelName) parallelName = 'Base';

    const { data: parRows } = await admin
      .from('set_parallels')
      .select('id, name, serial_max, is_auto, sort_order')
      .eq('set_id', vaultSetId)
      .order('sort_order', { ascending: true });

    const rows = (parRows ?? []) as { id: string; name: string; serial_max: number | null; is_auto: boolean; sort_order: number | null }[];
    let parallelId = resolveParallelId(rows, parallelName);

    if (!parallelId) {
      const serialFromName = serialMaxFromParallelName(parallelName);
      const maxSort = rows.reduce((m, r) => Math.max(m, r.sort_order ?? 0), 0);
      const ins = await admin
        .from('set_parallels')
        .upsert(
          {
            set_id: vaultSetId,
            name: parallelName.slice(0, 240),
            serial_max: serialFromName,
            is_auto: /\bauto(graph)?\b/i.test(parallelName),
            color_hex: null,
            sort_order: maxSort + 1,
            cardsight_id: null,
          },
          { onConflict: 'set_id,name' },
        )
        .select('id')
        .single();
      if (ins.error) throw new Error(ins.error.message);
      parallelId = ins.data!.id as string;
    }

    const { data: baseVar, error: bvErr } = await admin
      .from('set_card_base_variants')
      .select('id, set_card_id')
      .eq('set_id', vaultSetId)
      .eq('cardsight_card_id', cc)
      .maybeSingle();
    if (bvErr) throw new Error(bvErr.message);
    if (!baseVar) {
      throw new Error('set_card not found after import; try again or check cardsightCardId');
    }
    const baseMasterId = baseVar.id as string;
    const setCardId = baseVar.set_card_id as string;

    const { data: curPar } = await admin
      .from('master_card_definitions')
      .select('parallel_id')
      .eq('id', baseMasterId)
      .single();
    const baseParallelId = curPar?.parallel_id as string | undefined;

    let masterId = baseMasterId;
    if (parallelId && parallelId !== baseParallelId) {
      const { data: existing } = await admin
        .from('master_card_definitions')
        .select('id')
        .eq('set_card_id', setCardId)
        .eq('parallel_id', parallelId)
        .maybeSingle();
      if (existing?.id) {
        masterId = existing.id as string;
      } else {
        const { data: flags } = await admin
          .from('master_card_definitions')
          .select('is_auto, is_patch, is_ssp, serial_max')
          .eq('id', baseMasterId)
          .single();
        const { data: inserted, error: insErr } = await admin
          .from('master_card_definitions')
          .insert({
            set_card_id: setCardId,
            parallel_id: parallelId,
            is_auto: (flags?.is_auto as boolean) ?? false,
            is_patch: (flags?.is_patch as boolean) ?? false,
            is_ssp: (flags?.is_ssp as boolean) ?? false,
            serial_max: (flags?.serial_max as number | null) ?? null,
          })
          .select('id')
          .single();
        if (insErr) throw new Error(insErr.message);
        masterId = inserted!.id as string;
      }
    }

    const chKey =
      Deno.env.get('CARDHEDGE_API_KEY')?.trim() ||
      Deno.env.get('CARDHEDGER_API_KEY')?.trim() ||
      '';
    if (chId && chKey) {
      const h = await hydratePersistFieldsFromCardHedgeCardId(chKey, chId, { timeoutMs: 25_000 });
      await persistGuidePricesOntoMaster(admin, {
        masterVariantId: masterId,
        guidePriceCardId: chId,
        prices: h.prices,
        sales7d: h.sales7d,
        sales30d: h.sales30d,
        gain: h.gain,
        imageUrl: h.imageUrl,
      });
    }

    return json({
      masterCardDefinitionsId: masterId,
      setId: vaultSetId,
      releaseId: lazy.releaseId,
      parallelId,
    });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[catalog-ensure-from-scan-selection]', msg);
    return json({ error: msg }, 500);
  }
});
