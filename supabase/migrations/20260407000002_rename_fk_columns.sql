-- Rename FK columns to match the renamed hierarchy from migration 20260407000001:
--   sets.set_id          → release_id  (FK → releases)
--   set_parallels.checklist_id → set_id  (FK → sets)
--   master_card_definitions.checklist_id → set_id  (FK → sets)
--   pending_parallels.set_id: re-point FK from releases → sets (column name stays set_id)
--
-- The pending_parallels re-point also fixes a latent bug: the frontend was always
-- passing a set ID (not a release ID) to submit_pending_parallel(), but the FK
-- pointed to releases. Now the FK correctly points to sets.

-- ── 1. Drop the inventory view ────────────────────────────────────────────────
DROP VIEW IF EXISTS public.user_inventory_by_grade;

-- ── 2. sets.set_id → release_id ──────────────────────────────────────────────
ALTER TABLE public.sets RENAME COLUMN set_id TO release_id;
ALTER TABLE public.sets RENAME CONSTRAINT checklists_set_id_fkey        TO sets_release_id_fkey;
ALTER TABLE public.sets RENAME CONSTRAINT checklists_set_id_name_key    TO sets_release_id_name_key;

-- ── 3. set_parallels.checklist_id → set_id ───────────────────────────────────
ALTER TABLE public.set_parallels RENAME COLUMN checklist_id TO set_id;
ALTER TABLE public.set_parallels RENAME CONSTRAINT set_parallels_checklist_id_fkey         TO set_parallels_set_id_fkey;
ALTER TABLE public.set_parallels RENAME CONSTRAINT set_parallels_checklist_id_name_key     TO set_parallels_set_id_name_key;

-- ── 4. master_card_definitions.checklist_id → set_id ─────────────────────────
ALTER TABLE public.master_card_definitions RENAME COLUMN checklist_id TO set_id;
ALTER TABLE public.master_card_definitions RENAME CONSTRAINT master_card_definitions_checklist_id_fkey TO master_card_definitions_set_id_fkey;

-- ── 5. pending_parallels.set_id: re-point FK from releases → sets ─────────────
-- Column name stays set_id — it now correctly names what it references.
-- Existing rows held release IDs (the old incorrect FK target), so they cannot
-- be migrated to set IDs without knowing which set within each release was intended.
-- Clear them now; they will be re-submitted naturally as users add cards.
TRUNCATE TABLE public.pending_parallels;
ALTER TABLE public.pending_parallels DROP CONSTRAINT pending_parallels_set_id_fkey;
ALTER TABLE public.pending_parallels
  ADD CONSTRAINT pending_parallels_set_id_fkey
  FOREIGN KEY (set_id) REFERENCES public.sets(id) ON DELETE CASCADE;

-- ── 6. Recreate inventory view with updated column names ──────────────────────
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
LEFT JOIN public.sets s      ON m.set_id = s.id
LEFT JOIN public.releases r  ON s.release_id = r.id
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
-- NOTE: pending_parallels data was truncated and cannot be restored by rollback.
-- ALTER TABLE public.pending_parallels DROP CONSTRAINT pending_parallels_set_id_fkey;
-- ALTER TABLE public.pending_parallels ADD CONSTRAINT pending_parallels_set_id_fkey FOREIGN KEY (set_id) REFERENCES public.releases(id) ON DELETE CASCADE;
-- ALTER TABLE public.master_card_definitions RENAME CONSTRAINT master_card_definitions_set_id_fkey TO master_card_definitions_checklist_id_fkey;
-- ALTER TABLE public.master_card_definitions RENAME COLUMN set_id TO checklist_id;
-- ALTER TABLE public.set_parallels RENAME CONSTRAINT set_parallels_set_id_name_key TO set_parallels_checklist_id_name_key;
-- ALTER TABLE public.set_parallels RENAME CONSTRAINT set_parallels_set_id_fkey TO set_parallels_checklist_id_fkey;
-- ALTER TABLE public.set_parallels RENAME COLUMN set_id TO checklist_id;
-- ALTER TABLE public.sets RENAME CONSTRAINT sets_release_id_name_key TO checklists_set_id_name_key;
-- ALTER TABLE public.sets RENAME CONSTRAINT sets_release_id_fkey TO checklists_set_id_fkey;
-- ALTER TABLE public.sets RENAME COLUMN release_id TO set_id;
-- (then re-apply the view from migration 20260407000001)
