-- Refactor master_card_definitions to sit under checklists (not sets directly).
--
-- Changes:
--   ADD   checklist_id FK → checklists(id)
--   DROP  set_id        (redundant — access set via checklist JOIN)
--   DROP  set_name      (redundant — was a denormalized text copy)
--   DROP  parallel_type (moved to user_cards.parallel_id in next migration)
--
-- Kept: card_number, is_rookie, is_auto, is_patch, is_ssp, serial_max
-- These describe what the card physically IS, not which parallel skin it wears.

-- Drop the dependent view before altering the table.
-- It is recreated below using the new checklist-based joins.
DROP VIEW IF EXISTS public.user_inventory_by_grade;

ALTER TABLE public.master_card_definitions
  ADD COLUMN IF NOT EXISTS checklist_id uuid REFERENCES public.checklists(id) ON DELETE RESTRICT;

ALTER TABLE public.master_card_definitions
  DROP COLUMN IF EXISTS set_id,
  DROP COLUMN IF EXISTS set_name,
  DROP COLUMN IF EXISTS parallel_type;

-- NOTE: user_inventory_by_grade is recreated in 20260405000003_user_cards_parallel_id.sql
-- after parallel_id is added to user_cards.

-- ROLLBACK:
-- DROP VIEW IF EXISTS public.user_inventory_by_grade;
--
-- ALTER TABLE public.master_card_definitions
--   ADD COLUMN IF NOT EXISTS set_id       uuid REFERENCES public.sets(id),
--   ADD COLUMN IF NOT EXISTS set_name     text,
--   ADD COLUMN IF NOT EXISTS parallel_type text DEFAULT 'Base';
--
-- ALTER TABLE public.master_card_definitions
--   DROP COLUMN IF EXISTS checklist_id;
--
-- Restore original view after rollback:
-- CREATE OR REPLACE VIEW public.user_inventory_by_grade AS
-- SELECT u.user_id, m.id AS master_card_id, m.player, m.parallel_type,
--   s.name AS set_name, s.year, s.sport, u.is_graded, u.grader, u.grade_value,
--   count(u.id) AS quantity, sum(u.price_paid) AS total_cost,
--   avg(u.price_paid) AS avg_cost, sum(u.current_value) AS total_value,
--   avg(u.current_value) AS market_value_per_card
-- FROM public.user_cards u
-- JOIN public.master_card_definitions m ON u.master_card_id = m.id
-- LEFT JOIN public.sets s ON m.set_id = s.id
-- GROUP BY u.user_id, m.id, m.player, m.parallel_type,
--   s.name, s.year, s.sport, u.is_graded, u.grader, u.grade_value;
