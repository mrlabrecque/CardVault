/**
 * CardHedge image-search + merge helpers for `identify-card` (single client round-trip).
 * In **merge** mode, `identify-card` runs CardHedge image-search **first**, then CardSight,
 * and attaches CH variant/parallel imagery onto CardSight-shaped detections.
 */
const CH_IMAGE_SEARCH = 'https://api.cardhedger.com/v1/cards/image-search';

export type ChImageHit = {
  similarity: string;
  distance: number | null;
  card_id: string;
  player: string | null;
  set: string | null;
  number: string | null;
  variant: string | null;
  category: string | null;
  description: string | null;
  image: string | null;
};

function normalizeImageUrl(raw: string | null | undefined): string | null {
  if (!raw || typeof raw !== 'string') return null;
  const t = raw.trim();
  if (!t) return null;
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  if (t.startsWith('//')) return `https:${t}`;
  return t;
}

function parseSimilarityScore(sim: string): number {
  const n = parseFloat(String(sim).replace(/%/g, '').trim());
  if (!Number.isFinite(n)) return 0;
  if (n <= 1) return Math.max(0, Math.min(1, n));
  return Math.max(0, Math.min(1, n / 100));
}

export function normalizeChUpstreamHits(data: Record<string, unknown>): ChImageHit[] {
  const raw = data.results;
  if (!Array.isArray(raw)) return [];
  const out: ChImageHit[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const row = item as Record<string, unknown>;
    const cd = row.card_data;
    if (!cd || typeof cd !== 'object') continue;
    const c = cd as Record<string, unknown>;
    const cardId = String(c.card_id ?? '').trim();
    if (!cardId) continue;
    out.push({
      similarity: typeof row.similarity === 'string' ? row.similarity : String(row.similarity ?? ''),
      distance: typeof row.distance === 'number' && Number.isFinite(row.distance) ? row.distance : null,
      card_id: cardId,
      player: typeof c.player === 'string' ? c.player : null,
      set: typeof c.set === 'string' ? c.set : null,
      number: c.number == null ? null : String(c.number),
      variant: typeof c.variant === 'string' ? c.variant : null,
      category: typeof c.category === 'string' ? c.category : null,
      description: typeof c.description === 'string' ? c.description : null,
      image: typeof c.image === 'string' ? c.image : null,
    });
  }
  return out;
}

/** JSON-safe rows for `identify-card` → Flutter (CardHedge image-search picks). */
export function chHitsToJsonCandidates(hits: ChImageHit[], max = 25): Record<string, unknown>[] {
  const sorted = [...hits].sort((a, b) => parseSimilarityScore(b.similarity) - parseSimilarityScore(a.similarity));
  const cap = Math.min(50, Math.max(1, Math.trunc(max)));
  return sorted.slice(0, cap).map((h) => ({
    similarity: h.similarity,
    distance: h.distance,
    card_id: h.card_id,
    player: h.player,
    set: h.set,
    number: h.number,
    variant: h.variant,
    category: h.category,
    description: h.description,
    image: h.image,
  }));
}

export async function fetchCardHedgeImageSearchHits(
  apiKey: string,
  imageBase64Raw: string,
  k: number,
  opts?: { timeoutMs?: number },
): Promise<ChImageHit[]> {
  const upstreamBody: Record<string, unknown> = {
    k: Math.min(50, Math.max(1, Math.trunc(k))),
  };
  const trimmed = imageBase64Raw.trim();
  upstreamBody.image_base64 = trimmed.startsWith('data:')
    ? trimmed
    : `data:image/jpeg;base64,${trimmed}`;

  const timeoutMs = opts?.timeoutMs ?? 55_000;
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(CH_IMAGE_SEARCH, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      },
      body: JSON.stringify(upstreamBody),
      signal: controller.signal,
    });
    const text = await res.text();
    if (!res.ok) return [];
    let data: Record<string, unknown>;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      return [];
    }
    return normalizeChUpstreamHits(data);
  } catch {
    return [];
  } finally {
    clearTimeout(t);
  }
}

function normKey(s: string | null | undefined): string {
  if (!s) return '';
  return s.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function numbersRoughMatch(a: string | null | undefined, b: string | null | undefined): boolean {
  if (!a || !b) return false;
  const na = a.replace(/^#/, '').trim().toLowerCase();
  const nb = b.replace(/^#/, '').trim().toLowerCase();
  if (!na || !nb) return false;
  if (na === nb) return true;
  const ia = parseInt(na, 10);
  const ib = parseInt(nb, 10);
  return Number.isFinite(ia) && Number.isFinite(ib) && ia === ib;
}

function scoreDetectionToHit(
  det: Record<string, unknown>,
  hit: ChImageHit,
): number {
  let score = 0;
  score += parseSimilarityScore(hit.similarity) * 4;
  const card = det.card;
  const c = card && typeof card === 'object' ? (card as Record<string, unknown>) : null;
  const name = String(c?.name ?? c?.player ?? '').toLowerCase().trim();
  const hp = (hit.player ?? '').toLowerCase().trim();
  if (name && hp) {
    if (hp.includes(name) || name.includes(hp)) score += 8;
    else {
      const dTok = new Set(name.split(/\s+/).filter((x) => x.length > 2));
      const hTok = new Set(hp.split(/\s+/).filter((x) => x.length > 2));
      for (const x of dTok) {
        if (hTok.has(x)) {
          score += 5;
          break;
        }
      }
    }
  }
  const num = c ? String(c.number ?? c.cardNumber ?? c.card_number ?? '') : '';
  if (numbersRoughMatch(num, hit.number)) score += 10;
  return score;
}

const MIN_ACCEPT_SCORE = 6;

/** Mutates each CardSight-shaped detection: adds CardHedge fields + `vision_merge_debug`. */
export function mergeChHitsIntoCardSightDetections(
  detections: Record<string, unknown>[],
  hits: ChImageHit[],
): void {
  if (hits.length === 0 || detections.length === 0) return;
  const sorted = [...hits].sort((a, b) => parseSimilarityScore(b.similarity) - parseSimilarityScore(a.similarity));
  const used = new Set<number>();

  for (const det of detections) {
    let bestI = -1;
    let bestScore = -1;
    for (let i = 0; i < sorted.length; i++) {
      if (used.has(i)) continue;
      const s = scoreDetectionToHit(det, sorted[i]!);
      if (s > bestScore) {
        bestScore = s;
        bestI = i;
      }
    }

    const card = det.card;
    const origCard =
      card && typeof card === 'object' ? JSON.parse(JSON.stringify(card)) as Record<string, unknown> : {};
    const c = card && typeof card === 'object' ? ({ ...(card as Record<string, unknown>) }) : {};

    if (bestI >= 0 && bestScore >= MIN_ACCEPT_SCORE) {
      used.add(bestI);
      const h = sorted[bestI]!;
      const sim = parseSimilarityScore(h.similarity);
      det.cardHedgeCardId = h.card_id;
      det.cardHedgeVariant = h.variant;
      det.cardHedgeSetLabel = h.set;
      det.cardHedgeImageSimilarity = sim;

      const par = c.parallel;
      const hasPar = par && typeof par === 'object' && String((par as Record<string, unknown>).name ?? '').trim();
      if (!hasPar && h.variant && h.variant.trim()) {
        c.parallel = { id: '', name: h.variant.trim(), numberedTo: null };
      }
      const img = normalizeImageUrl(h.image);
      if (img && (!c.imageUrl || String(c.imageUrl).trim() === '')) {
        c.imageUrl = img;
      }
      det.card = c;

      det.vision_merge_debug = {
        strategy: 'cardhedge_on_cardsight',
        accepted: true,
        score: bestScore,
        threshold: MIN_ACCEPT_SCORE,
        cardhedge_hit: h,
        cardsight_detection_before_merge: origCard,
        merged_card: c,
        merged_root_fields: {
          cardHedgeCardId: det.cardHedgeCardId,
          cardHedgeVariant: det.cardHedgeVariant,
          cardHedgeSetLabel: det.cardHedgeSetLabel,
          cardHedgeImageSimilarity: det.cardHedgeImageSimilarity,
        },
      };
    } else {
      det.vision_merge_debug = {
        strategy: 'cardhedge_on_cardsight',
        accepted: false,
        best_score: bestScore,
        threshold: MIN_ACCEPT_SCORE,
        cardhedge_candidates: sorted.slice(0, 8),
        cardsight_detection: origCard,
      };
    }
  }
}

/**
 * After [mergeChHitsIntoCardSightDetections], overwrite `det.card.cardsightReleaseId` /
 * `cardsightSetId` with the spine from [cardhedge_candidates] for the matched CH row.
 * CardSight vision often confuses NBA vs WNBA Prizm; CH + vault/catalog spine is more reliable.
 */
export function applyChEnrichedSpineToMergedDetections(
  candidates: Record<string, unknown>[] | null | undefined,
  detections: Record<string, unknown>[],
): void {
  if (!candidates?.length || detections.length === 0) return;
  const byCardId = new Map<string, Record<string, unknown>>();
  for (const row of candidates) {
    const id = String(row.card_id ?? '').trim();
    if (id) byCardId.set(id, row);
  }
  for (const det of detections) {
    const hid = String(det.cardHedgeCardId ?? '').trim();
    if (!hid) continue;
    const row = byCardId.get(hid);
    if (!row) continue;
    const cr = String(row.cardsightReleaseId ?? '').trim();
    const cs = String(row.cardsightSetId ?? '').trim();
    if (!cr || !cs) continue;
    const card = det.card;
    if (!card || typeof card !== 'object') continue;
    const cm = card as Record<string, unknown>;
    cm.cardsightReleaseId = cr;
    cm.cardsightSetId = cs;
  }
}

function extractYearFromSetLabel(setLabel: string | null | undefined): string | null {
  if (!setLabel) return null;
  const m = setLabel.match(/\b(19|20)\d{2}\b/);
  return m ? m[0]! : null;
}

/** One detection row per CardHedge hit (CardSight-shaped envelope for Flutter). */
export function detectionsFromChHitsOnly(hits: ChImageHit[], sportSlug: string): Record<string, unknown>[] {
  const sorted = [...hits].sort((a, b) => parseSimilarityScore(b.similarity) - parseSimilarityScore(a.similarity));
  const out: Record<string, unknown>[] = [];
  let rank = 0;
  for (const h of sorted) {
    rank++;
    const sim = parseSimilarityScore(h.similarity);
    const year = extractYearFromSetLabel(h.set) ?? '';
    const img = normalizeImageUrl(h.image);
    const det: Record<string, unknown> = {
      confidence: sim >= 0.85 ? 'High' : sim >= 0.65 ? 'Medium' : 'Low',
      matchScore: sim,
      card: {
        name: h.player ?? '',
        number: h.number ?? '',
        year,
        releaseName: h.set ?? '',
        setName: h.set ?? '',
        parallel: h.variant && h.variant.trim()
          ? { id: '', name: h.variant.trim(), numberedTo: null }
          : null,
        imageUrl: img,
        segmentId: sportSlug,
      },
      cardHedgeCardId: h.card_id,
      cardHedgeVariant: h.variant,
      cardHedgeSetLabel: h.set,
      cardHedgeImageSimilarity: sim,
      vision_merge_debug: {
        strategy: 'cardhedge_only',
        rank,
        cardhedge_hit: h,
        built_card: {
          name: h.player,
          number: h.number,
          set: h.set,
          variant: h.variant,
          image: img,
        },
        note: 'No CardSight call — open catalog to search by player/set if UUIDs are missing.',
      },
    };
    out.push(det);
  }
  return out;
}
