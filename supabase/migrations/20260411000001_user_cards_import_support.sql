-- Option A: CSV-imported cards live directly in user_cards without a master_card_definitions entry.
-- The catalog (master_card_definitions) stays clean — only CardSight-sourced cards go there.
--
-- Changes:
--   1. master_card_id becomes nullable  (NULL = imported card, not linked to catalog)
--   2. Denormalized card fields added to user_cards for import rows
--   3. user_inventory_by_grade view updated to LEFT JOIN and COALESCE from both sources

-- ── 1. Make master_card_id nullable ──────────────────────────────────────────
ALTER TABLE public.user_cards
  ALTER COLUMN master_card_id DROP NOT NULL;

-- ── 2. Add denormalized fields for import rows ────────────────────────────────
-- These are only populated when master_card_id IS NULL (i.e. CSV-imported cards).
ALTER TABLE public.user_cards
  ADD COLUMN IF NOT EXISTS player      text,
  ADD COLUMN IF NOT EXISTS card_number text,
  ADD COLUMN IF NOT EXISTS is_rookie   boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_auto     boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_patch    boolean NOT NULL DEFAULT false;

-- ── 3. Recreate inventory view to handle both linked and unlinked rows ────────
DROP VIEW IF EXISTS public.user_inventory_by_grade;

CREATE OR REPLACE VIEW public.user_inventory_by_grade AS
SELECT
  u.user_id,
  m.id                                      AS master_card_id,
  COALESCE(m.player, u.player)              AS player,
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
LEFT JOIN public.sets s                    ON m.set_id = s.id
LEFT JOIN public.releases r                ON s.release_id = r.id
LEFT JOIN public.set_parallels p           ON u.parallel_id = p.id
GROUP BY
  u.user_id,
  m.id,
  COALESCE(m.player, u.player),
  p.name,
  r.name,
  s.name,
  r.year,
  r.sport,
  u.is_graded,
  u.grader,
  u.grade_value;
