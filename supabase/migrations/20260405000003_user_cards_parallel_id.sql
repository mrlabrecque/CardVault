-- Add parallel_id to user_cards so each owned card instance records which parallel skin it is.
-- Nullable: a NULL parallel_id means Base (no parallel), which is valid.
-- ON DELETE SET NULL: if a parallel is removed from the catalog, the card is not deleted —
-- it just loses its parallel association and can be re-linked.

ALTER TABLE public.user_cards
  ADD COLUMN IF NOT EXISTS parallel_id uuid REFERENCES public.set_parallels(id) ON DELETE SET NULL;

-- Recreate the inventory view now that both checklist_id (migration 2) and
-- parallel_id (this migration) are in place.
DROP VIEW IF EXISTS public.user_inventory_by_grade;

CREATE OR REPLACE VIEW public.user_inventory_by_grade AS
SELECT
  u.user_id,
  m.id                          AS master_card_id,
  m.player,
  p.name                        AS parallel_name,
  s.name                        AS set_name,
  s.year,
  s.sport,
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
LEFT JOIN public.checklists c ON m.checklist_id = c.id
LEFT JOIN public.sets s ON c.set_id = s.id
LEFT JOIN public.set_parallels p ON u.parallel_id = p.id
GROUP BY
  u.user_id,
  m.id,
  m.player,
  p.name,
  s.name,
  s.year,
  s.sport,
  u.is_graded,
  u.grader,
  u.grade_value;

-- ROLLBACK:
-- DROP VIEW IF EXISTS public.user_inventory_by_grade;
-- ALTER TABLE public.user_cards DROP COLUMN IF EXISTS parallel_id;
-- Restore original view (see migration 2 rollback block for the SQL).
