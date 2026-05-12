-- Split checklist rows into set_cards + per-parallel master_card_definitions (catalog variants).
-- user_cards.master_card_id becomes FK to master_card_definitions (variant), not set_cards.

-- ── 0. Dependents that reference master_card_definitions by name ─────────────
DROP VIEW IF EXISTS public.user_inventory_by_grade;

ALTER TABLE public.user_cards
  DROP CONSTRAINT IF EXISTS user_cards_master_card_id_fkey;

ALTER TABLE public.wishlist
  DROP CONSTRAINT IF EXISTS wishlist_master_card_id_fkey;

ALTER TABLE public.card_sold_comps
  DROP CONSTRAINT IF EXISTS card_sold_comps_master_card_id_fkey;

ALTER TABLE public.card_comps_refresh_log
  DROP CONSTRAINT IF EXISTS card_comps_refresh_log_master_card_id_fkey;

-- ── 1. Preserve legacy checklist table ───────────────────────────────────────
ALTER TABLE public.master_card_definitions
  RENAME TO legacy_master_card_checklist;

-- ── 2. New checklist table (CardSight / base card art on image_url) ─────────
CREATE TABLE public.set_cards (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  set_id          uuid NOT NULL REFERENCES public.sets(id) ON DELETE RESTRICT,
  player          text NOT NULL,
  card_number     text,
  is_rookie       boolean NOT NULL DEFAULT false,
  image_url       text,
  cardsight_card_id text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT set_cards_cardsight_card_id_key UNIQUE (cardsight_card_id)
);

CREATE INDEX set_cards_set_id_idx ON public.set_cards (set_id);

CREATE UNIQUE INDEX set_cards_set_player_number_uq
  ON public.set_cards (set_id, player, card_number)
  WHERE card_number IS NOT NULL;

CREATE UNIQUE INDEX set_cards_set_player_null_number_uq
  ON public.set_cards (set_id, player)
  WHERE card_number IS NULL;

COMMENT ON TABLE public.set_cards IS
  'Checklist line per set (player + card #); CardSight image_url; unique per (set, player, card_number).';

-- ── 3. Copy rows + build legacy_id → set_card_id map ─────────────────────────
INSERT INTO public.set_cards (set_id, player, card_number, is_rookie, image_url, cardsight_card_id, created_at)
SELECT
  l.set_id,
  l.player,
  l.card_number,
  COALESCE(l.is_rookie, false),
  l.image_url,
  l.cardsight_card_id,
  COALESCE(l.created_at, now())
FROM public.legacy_master_card_checklist l
WHERE l.set_id IS NOT NULL;

CREATE TABLE public._legacy_master_to_set_card (
  legacy_id    uuid PRIMARY KEY,
  set_card_id  uuid NOT NULL REFERENCES public.set_cards(id) ON DELETE CASCADE
);

INSERT INTO public._legacy_master_to_set_card (legacy_id, set_card_id)
SELECT l.id, s.id
FROM public.legacy_master_card_checklist l
JOIN public.set_cards s
  ON s.set_id = l.set_id
 AND s.player = l.player
 AND (s.card_number IS NOT DISTINCT FROM l.card_number)
WHERE l.set_id IS NOT NULL;

-- Orphan checklist rows (no set_id): unlink collections that pointed at them
UPDATE public.user_cards uc
SET master_card_id = NULL
FROM public.legacy_master_card_checklist l
WHERE uc.master_card_id = l.id
  AND l.set_id IS NULL;

-- ── 4. Catalog variants (parallel + flags + CardHedge columns) ───────────────
CREATE TABLE public.master_card_definitions (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  set_card_id           uuid NOT NULL REFERENCES public.set_cards(id) ON DELETE CASCADE,
  parallel_id           uuid NOT NULL REFERENCES public.set_parallels(id) ON DELETE RESTRICT,
  is_auto               boolean NOT NULL DEFAULT false,
  is_patch              boolean NOT NULL DEFAULT false,
  is_ssp                boolean NOT NULL DEFAULT false,
  serial_max            integer,
  cardhedge_id          text,
  image_url             text,
  sales_7d              numeric,
  sales_30d             numeric,
  gain                  numeric,
  cardhedge_fetched_at  timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT master_card_definitions_set_card_parallel_uq UNIQUE (set_card_id, parallel_id)
);

CREATE INDEX master_card_definitions_set_card_id_idx ON public.master_card_definitions (set_card_id);
CREATE INDEX master_card_definitions_parallel_id_idx ON public.master_card_definitions (parallel_id);
CREATE INDEX master_card_definitions_cardhedge_id_idx ON public.master_card_definitions (cardhedge_id);

COMMENT ON TABLE public.master_card_definitions IS
  'Per-parallel catalog variant: flags, CardHedge id/market fields, parallel image_url (Storage).';

COMMENT ON COLUMN public.set_cards.image_url IS 'CardSight checklist image.';
COMMENT ON COLUMN public.master_card_definitions.image_url IS 'Parallel image (e.g. CardHedge → Storage); preferred over set_cards.image_url in UI.';

-- Helper: pick default parallel for a set (Base first, else lowest sort_order).
CREATE OR REPLACE FUNCTION public._default_parallel_for_set(p_set_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT sp.id
  FROM public.set_parallels sp
  WHERE sp.set_id = p_set_id
  ORDER BY
    CASE WHEN lower(trim(sp.name)) = 'base' THEN 0 ELSE 1 END,
    sp.sort_order NULLS LAST,
    sp.name
  LIMIT 1;
$$;

-- 4a. Base variant for every set_card that has at least one parallel
INSERT INTO public.master_card_definitions (
  set_card_id, parallel_id, is_auto, is_patch, is_ssp, serial_max
)
SELECT
  sc.id,
  public._default_parallel_for_set(sc.set_id),
  COALESCE(leg.is_auto, false),
  COALESCE(leg.is_patch, false),
  COALESCE(leg.is_ssp, false),
  leg.serial_max
FROM public.set_cards sc
JOIN public._legacy_master_to_set_card t ON t.set_card_id = sc.id
JOIN public.legacy_master_card_checklist leg ON leg.id = t.legacy_id
WHERE public._default_parallel_for_set(sc.set_id) IS NOT NULL;

-- 4b. Variants for parallels actually used on user_cards (same flags from legacy row)
INSERT INTO public.master_card_definitions (
  set_card_id, parallel_id, is_auto, is_patch, is_ssp, serial_max
)
SELECT DISTINCT
  sc.id,
  uc.parallel_id,
  COALESCE(leg.is_auto, false),
  COALESCE(leg.is_patch, false),
  COALESCE(leg.is_ssp, false),
  leg.serial_max
FROM public.user_cards uc
JOIN public._legacy_master_to_set_card t ON t.legacy_id = uc.master_card_id
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.legacy_master_card_checklist leg ON leg.id = t.legacy_id
JOIN public.set_parallels sp ON sp.id = uc.parallel_id AND sp.set_id = sc.set_id
WHERE uc.master_card_id IS NOT NULL
  AND uc.parallel_id IS NOT NULL
ON CONFLICT ON CONSTRAINT master_card_definitions_set_card_parallel_uq DO NOTHING;

-- ── 5. Repoint user_cards.master_card_id to variant id ───────────────────────
UPDATE public.user_cards uc
SET master_card_id = m.id
FROM public._legacy_master_to_set_card t
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.master_card_definitions m ON m.set_card_id = sc.id
WHERE uc.master_card_id = t.legacy_id
  AND uc.parallel_id IS NOT NULL
  AND m.parallel_id = uc.parallel_id;

UPDATE public.user_cards uc
SET
  master_card_id = m.id,
  parallel_id = COALESCE(uc.parallel_id, public._default_parallel_for_set(sc.set_id))
FROM public._legacy_master_to_set_card t
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.master_card_definitions m ON m.set_card_id = sc.id
WHERE uc.master_card_id = t.legacy_id
  AND uc.parallel_id IS NULL
  AND m.parallel_id = public._default_parallel_for_set(sc.set_id);

-- Any user_cards still pointing at a legacy checklist id → base variant
UPDATE public.user_cards uc
SET
  master_card_id = m.id,
  parallel_id = COALESCE(uc.parallel_id, m.parallel_id)
FROM public._legacy_master_to_set_card t
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.master_card_definitions m
  ON m.set_card_id = sc.id
 AND m.parallel_id = public._default_parallel_for_set(sc.set_id)
WHERE uc.master_card_id = t.legacy_id;

-- ── 6. card_sold_comps: legacy checklist id → variant (match parallel_name) ─
UPDATE public.card_sold_comps csc
SET master_card_id = m.id
FROM public._legacy_master_to_set_card t
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.master_card_definitions m ON m.set_card_id = sc.id
JOIN public.set_parallels p ON p.id = m.parallel_id
WHERE csc.master_card_id = t.legacy_id
  AND csc.parallel_name IS NOT NULL
  AND lower(trim(regexp_replace(csc.parallel_name, '\s+', ' ', 'g')))
      = lower(trim(regexp_replace(p.name, '\s+', ' ', 'g')));

UPDATE public.card_sold_comps csc
SET master_card_id = m.id
FROM public._legacy_master_to_set_card t
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.master_card_definitions m ON m.set_card_id = sc.id
WHERE csc.master_card_id = t.legacy_id
  AND m.parallel_id = public._default_parallel_for_set(sc.set_id);

-- ── 7. card_comps_refresh_log: remap + simplify PK to variant id ─────────────
UPDATE public.card_comps_refresh_log r
SET master_card_id = m.id
FROM public._legacy_master_to_set_card t
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.master_card_definitions m ON m.set_card_id = sc.id
JOIN public.set_parallels p ON p.id = m.parallel_id
WHERE r.master_card_id = t.legacy_id
  AND lower(trim(regexp_replace(r.parallel_name, '\s+', ' ', 'g')))
      = lower(trim(regexp_replace(p.name, '\s+', ' ', 'g')));

UPDATE public.card_comps_refresh_log r
SET master_card_id = m.id
FROM public._legacy_master_to_set_card t
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.master_card_definitions m ON m.set_card_id = sc.id
WHERE r.master_card_id = t.legacy_id
  AND m.parallel_id = public._default_parallel_for_set(sc.set_id);

DELETE FROM public.card_comps_refresh_log a
USING public.card_comps_refresh_log b
WHERE a.master_card_id = b.master_card_id
  AND a.ctid < b.ctid;

ALTER TABLE public.card_comps_refresh_log
  DROP CONSTRAINT IF EXISTS card_comps_refresh_log_pkey;

ALTER TABLE public.card_comps_refresh_log
  ADD CONSTRAINT card_comps_refresh_log_pkey PRIMARY KEY (master_card_id);

-- ── 8. wishlist.master_card_id → variant ────────────────────────────────────
UPDATE public.wishlist w
SET master_card_id = m.id
FROM public._legacy_master_to_set_card t
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.master_card_definitions m ON m.set_card_id = sc.id
JOIN public.set_parallels p ON p.id = m.parallel_id
WHERE w.master_card_id = t.legacy_id
  AND w.parallel IS NOT NULL
  AND lower(trim(regexp_replace(w.parallel, '\s+', ' ', 'g')))
      = lower(trim(regexp_replace(p.name, '\s+', ' ', 'g')));

UPDATE public.wishlist w
SET master_card_id = m.id
FROM public._legacy_master_to_set_card t
JOIN public.set_cards sc ON sc.id = t.set_card_id
JOIN public.master_card_definitions m ON m.set_card_id = sc.id
WHERE w.master_card_id = t.legacy_id
  AND m.parallel_id = public._default_parallel_for_set(sc.set_id);

-- Clear wishlist rows that still reference deleted legacy ids (no catalog row)
UPDATE public.wishlist w
SET master_card_id = NULL
WHERE w.master_card_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.master_card_definitions m WHERE m.id = w.master_card_id);

-- Remove comps refresh rows we could not map to a variant
DELETE FROM public.card_comps_refresh_log r
WHERE NOT EXISTS (SELECT 1 FROM public.master_card_definitions m WHERE m.id = r.master_card_id);

DELETE FROM public.card_sold_comps c
WHERE c.master_card_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.master_card_definitions m WHERE m.id = c.master_card_id);

DELETE FROM public.card_comps_refresh_log WHERE master_card_id IS NULL;

-- Unmapped catalog links (legacy ids not promoted to a variant row)
UPDATE public.user_cards uc
SET master_card_id = NULL
WHERE uc.master_card_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.master_card_definitions m WHERE m.id = uc.master_card_id);

-- ── 9. Drop legacy + map + helper ────────────────────────────────────────────
DROP TABLE public.legacy_master_card_checklist CASCADE;
DROP TABLE public._legacy_master_to_set_card;

DROP FUNCTION IF EXISTS public._default_parallel_for_set(uuid);

-- ── 10. FKs back onto new master_card_definitions ───────────────────────────
ALTER TABLE public.user_cards
  ADD CONSTRAINT user_cards_master_card_id_fkey
  FOREIGN KEY (master_card_id) REFERENCES public.master_card_definitions(id) ON DELETE RESTRICT;

ALTER TABLE public.wishlist
  ADD CONSTRAINT wishlist_master_card_id_fkey
  FOREIGN KEY (master_card_id) REFERENCES public.master_card_definitions(id) ON DELETE SET NULL;

ALTER TABLE public.card_sold_comps
  ADD CONSTRAINT card_sold_comps_master_card_id_fkey
  FOREIGN KEY (master_card_id) REFERENCES public.master_card_definitions(id) ON DELETE CASCADE;

ALTER TABLE public.card_comps_refresh_log
  ADD CONSTRAINT card_comps_refresh_log_master_card_id_fkey
  FOREIGN KEY (master_card_id) REFERENCES public.master_card_definitions(id) ON DELETE CASCADE;

-- ── 11. current_prices (CardHedge grade rows, etc.) ───────────────────────────
CREATE TABLE public.current_prices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  master_card_id  uuid NOT NULL REFERENCES public.master_card_definitions(id) ON DELETE CASCADE,
  grade           text NOT NULL,
  price           numeric,
  currency        text NOT NULL DEFAULT 'USD',
  raw             jsonb,
  fetched_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT current_prices_master_grade_uq UNIQUE (master_card_id, grade)
);

CREATE INDEX current_prices_master_card_id_idx ON public.current_prices (master_card_id);

ALTER TABLE public.current_prices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Auth users read current_prices"
  ON public.current_prices FOR SELECT TO authenticated USING (true);

-- ── 12. RLS: set_cards + master_card_definitions ───────────────────────────
ALTER TABLE public.set_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_card_definitions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "set_cards public read"
  ON public.set_cards FOR SELECT USING (true);

CREATE POLICY "set_cards authenticated insert"
  ON public.set_cards FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "master_card_definitions public read"
  ON public.master_card_definitions FOR SELECT USING (true);

CREATE POLICY "master_card_definitions authenticated insert"
  ON public.master_card_definitions FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.set_cards sc WHERE sc.id = set_card_id)
    AND EXISTS (
      SELECT 1
      FROM public.set_parallels sp
      JOIN public.set_cards sc2 ON sc2.id = set_card_id
      WHERE sp.id = parallel_id AND sp.set_id = sc2.set_id
    )
  );

-- ── 13. portfolio_movers_from_vault ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.portfolio_movers_from_vault(p_sport text DEFAULT NULL)
RETURNS TABLE (
  player_key text,
  player_name text,
  sport text,
  card_count bigint,
  avg_current numeric,
  avg_previous numeric,
  price_change_pct double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base AS (
    SELECT
      trim(both from sc.player) AS pn,
      trim(both from coalesce(r.sport::text, '')) AS spr,
      u.current_value::numeric AS cv,
      u.previous_value::numeric AS pv
    FROM public.user_cards u
    INNER JOIN public.master_card_definitions m ON m.id = u.master_card_id
    INNER JOIN public.set_cards sc ON sc.id = m.set_card_id
    INNER JOIN public.sets s ON s.id = sc.set_id
    INNER JOIN public.releases r ON r.id = s.release_id
    WHERE u.current_value IS NOT NULL
      AND u.previous_value IS NOT NULL
      AND u.previous_value > 0
      AND trim(both from coalesce(sc.player, '')) <> ''
  ),
  agg AS (
    SELECT
      pn AS agg_player,
      spr AS agg_sport,
      COUNT(*)::bigint AS cnt,
      AVG(cv) AS avg_cur,
      AVG(pv) AS avg_prev
    FROM base
    GROUP BY pn, spr
  )
  SELECT
    md5(agg.agg_player || '|' || agg.agg_sport)::text AS player_key,
    agg.agg_player::text AS player_name,
    agg.agg_sport::text AS sport,
    agg.cnt AS card_count,
    round(agg.avg_cur, 2) AS avg_current,
    round(agg.avg_prev, 2) AS avg_previous,
    CASE
      WHEN agg.avg_prev > 0 THEN
        ((agg.avg_cur - agg.avg_prev) / agg.avg_prev * 100)::double precision
      ELSE 0::double precision
    END AS price_change_pct
  FROM agg
  WHERE (p_sport IS NULL OR trim(both from agg.agg_sport) = trim(both from p_sport));
$$;

COMMENT ON FUNCTION public.portfolio_movers_from_vault(text) IS
  'Portfolio movers: avg(current_value) vs avg(previous_value) across all collections per player/sport; optional sport filter (releases.sport).';

REVOKE ALL ON FUNCTION public.portfolio_movers_from_vault(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portfolio_movers_from_vault(text) TO authenticated;

-- ── 14. user_inventory_by_grade view ─────────────────────────────────────────
CREATE OR REPLACE VIEW public.user_inventory_by_grade AS
SELECT
  u.user_id,
  m.id                                      AS master_card_id,
  COALESCE(sc.player, u.player)             AS player,
  p.name                                    AS parallel_name,
  r.name                                    AS release_name,
  s.name                                    AS set_name,
  r.year,
  r.sport,
  u.is_graded,
  u.grader,
  u.grade_value,
  count(u.id)                               AS quantity,
  sum(u.price_paid)                         AS total_cost,
  avg(u.price_paid)                         AS avg_cost,
  sum(u.current_value)                      AS total_value,
  avg(u.current_value)                      AS market_value_per_card
FROM public.user_cards u
LEFT JOIN public.master_card_definitions m ON u.master_card_id = m.id
LEFT JOIN public.set_cards sc             ON m.set_card_id = sc.id
LEFT JOIN public.sets s                   ON sc.set_id = s.id
LEFT JOIN public.releases r               ON s.release_id = r.id
LEFT JOIN public.set_parallels p          ON u.parallel_id = p.id
GROUP BY
  u.user_id,
  m.id,
  COALESCE(sc.player, u.player),
  p.name,
  r.name,
  s.name,
  r.year,
  r.sport,
  u.is_graded,
  u.grader,
  u.grade_value;

GRANT SELECT ON public.user_inventory_by_grade TO authenticated;

-- Grants for PostgREST
GRANT SELECT ON public.set_cards TO anon, authenticated;
GRANT INSERT ON public.set_cards TO authenticated;
GRANT SELECT ON public.master_card_definitions TO anon, authenticated;
GRANT INSERT ON public.master_card_definitions TO authenticated;
GRANT SELECT ON public.current_prices TO authenticated;

-- Search/browse: one row per checklist line with Base parallel variant id as `id`
-- (so comps + fetch-card-image + add-card can use a single id consistently).
CREATE OR REPLACE VIEW public.set_card_base_variants AS
SELECT DISTINCT ON (sc.id)
  m.id,
  sc.id AS set_card_id,
  sc.set_id,
  sc.player,
  sc.card_number,
  sc.is_rookie,
  m.is_auto,
  m.is_patch,
  m.is_ssp,
  m.serial_max,
  COALESCE(NULLIF(m.image_url, ''), sc.image_url) AS image_url,
  sc.cardsight_card_id
FROM public.set_cards sc
INNER JOIN public.master_card_definitions m ON m.set_card_id = sc.id
INNER JOIN public.set_parallels p ON p.id = m.parallel_id
ORDER BY
  sc.id,
  CASE WHEN lower(trim(p.name)) = 'base' THEN 0 ELSE 1 END,
  p.sort_order NULLS LAST,
  p.name;

GRANT SELECT ON public.set_card_base_variants TO anon, authenticated;

GRANT ALL ON public.set_cards TO service_role;
GRANT ALL ON public.master_card_definitions TO service_role;
GRANT ALL ON public.current_prices TO service_role;
