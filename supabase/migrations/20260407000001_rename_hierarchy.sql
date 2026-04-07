-- Rename hierarchy to align with CardSight AI API terminology:
--   sets        → releases   (top-level product, e.g. "2025 Topps Chrome")
--   checklists  → sets       (subset within a release, e.g. "Base", "Heavy Hitters")
--   pending_sets → pending_releases
--
-- Column names (set_id, checklist_id) are left as-is — FK semantics are clear
-- from context and renaming FK columns across many tables is unnecessary churn.

-- ── 1. Drop the view that references old table names ──────────────────────────
DROP VIEW IF EXISTS public.user_inventory_by_grade;

-- ── 2. Rename sets → releases ─────────────────────────────────────────────────
ALTER TABLE public.sets RENAME TO releases;

-- Rename RLS policies on releases (was sets)
ALTER POLICY "Authenticated users can read sets"  ON public.releases RENAME TO "Authenticated users can read releases";
ALTER POLICY "App admins can insert sets"          ON public.releases RENAME TO "App admins can insert releases";
ALTER POLICY "App admins can update sets"          ON public.releases RENAME TO "App admins can update releases";
ALTER POLICY "App admins can delete sets"          ON public.releases RENAME TO "App admins can delete releases";

-- ── 3. Rename checklists → sets ───────────────────────────────────────────────
ALTER TABLE public.checklists RENAME TO sets;

-- Rename RLS policies on sets (was checklists)
ALTER POLICY "Authenticated users can read checklists"  ON public.sets RENAME TO "Authenticated users can read sets";
ALTER POLICY "App admins can insert checklists"          ON public.sets RENAME TO "App admins can insert sets";
ALTER POLICY "App admins can update checklists"          ON public.sets RENAME TO "App admins can update sets";
ALTER POLICY "App admins can delete checklists"          ON public.sets RENAME TO "App admins can delete sets";

-- ── 4. Rename pending_sets → pending_releases ─────────────────────────────────
ALTER TABLE public.pending_sets RENAME TO pending_releases;

-- Rename RLS policies on pending_releases (was pending_sets)
ALTER POLICY "Authenticated users can submit pending sets"          ON public.pending_releases RENAME TO "Authenticated users can submit pending releases";
ALTER POLICY "Authenticated users can increment pending set count"  ON public.pending_releases RENAME TO "Authenticated users can increment pending release count";
ALTER POLICY "App admins can read pending sets"                     ON public.pending_releases RENAME TO "App admins can read pending releases";
ALTER POLICY "App admins can delete pending sets"                   ON public.pending_releases RENAME TO "App admins can delete pending releases";

-- Rename trigger and function for pending_releases
ALTER TRIGGER pending_sets_updated_at ON public.pending_releases
  RENAME TO pending_releases_updated_at;

ALTER FUNCTION public.update_pending_sets_updated_at()
  RENAME TO update_pending_releases_updated_at;

-- ── 5. Recreate inventory view with new table names ───────────────────────────
-- Now: master_card_definitions.checklist_id → sets (was checklists)
--      sets.set_id → releases (was sets)
CREATE OR REPLACE VIEW public.user_inventory_by_grade AS
SELECT
  u.user_id,
  m.id                          AS master_card_id,
  m.player,
  p.name                        AS parallel_name,
  r.name                        AS release_name,
  s.name                        AS set_name,
  r.year,
  r.sport,
  u.is_graded,
  u.grader,
  u.grade_value,
  count(u.id)                   AS quantity,
  sum(u.price_paid)             AS total_cost,
  avg(u.price_paid)             AS avg_cost,
  sum(u.current_value)          AS total_value,
  avg(u.current_value)          AS market_value_per_card
FROM public.user_cards u
JOIN public.master_card_definitions m ON u.master_card_id = m.id
LEFT JOIN public.sets s      ON m.checklist_id = s.id
LEFT JOIN public.releases r  ON s.set_id = r.id
LEFT JOIN public.set_parallels p ON u.parallel_id = p.id
GROUP BY
  u.user_id,
  m.id,
  m.player,
  p.name,
  r.name,
  s.name,
  r.year,
  r.sport,
  u.is_graded,
  u.grader,
  u.grade_value;

-- ROLLBACK:
-- DROP VIEW IF EXISTS public.user_inventory_by_grade;
-- ALTER FUNCTION public.update_pending_releases_updated_at() RENAME TO update_pending_sets_updated_at;
-- ALTER TRIGGER pending_releases_updated_at ON public.pending_releases RENAME TO pending_sets_updated_at;
-- ALTER TABLE public.pending_releases RENAME TO pending_sets;
-- ALTER TABLE public.sets RENAME TO checklists;
-- ALTER TABLE public.releases RENAME TO sets;
-- (then re-apply migration 20260405000005 to restore the original view)
