-- Move set_parallels from set-level to checklist-level.
-- Each checklist (including the auto-created "Base Set") owns its own parallel list.
-- This lets inserts (Fireworks, Monopoly Money, etc.) have independent parallels
-- from the base set, which is the real-world model.

-- 1. Drop the inventory view that joins through set_parallels
DROP VIEW IF EXISTS public.user_inventory_by_grade;

-- 2. Add checklist_id (nullable for now so we can migrate data)
ALTER TABLE public.set_parallels
  ADD COLUMN IF NOT EXISTS checklist_id uuid REFERENCES public.checklists(id) ON DELETE CASCADE;

-- 3. Ensure every set has at least a Base Set checklist (null prefix)
--    so we have something to point existing parallels at.
INSERT INTO public.checklists (set_id, name, prefix)
SELECT s.id, 'Base Set', NULL
FROM public.sets s
WHERE NOT EXISTS (
  SELECT 1 FROM public.checklists c
  WHERE c.set_id = s.id AND c.prefix IS NULL
)
ON CONFLICT (set_id, name) DO NOTHING;

-- 4. Point all existing parallels at their set's base checklist
UPDATE public.set_parallels sp
SET checklist_id = c.id
FROM public.checklists c
WHERE c.set_id = sp.set_id
  AND c.prefix IS NULL
  AND sp.checklist_id IS NULL;

-- 5. Make checklist_id NOT NULL now that every row has been filled
ALTER TABLE public.set_parallels
  ALTER COLUMN checklist_id SET NOT NULL;

-- 6. Drop the old set_id column and its unique constraint
ALTER TABLE public.set_parallels
  DROP CONSTRAINT IF EXISTS set_parallels_set_id_name_key;

ALTER TABLE public.set_parallels
  DROP COLUMN IF EXISTS set_id;

-- 7. New unique constraint scoped to checklist
ALTER TABLE public.set_parallels
  ADD CONSTRAINT set_parallels_checklist_id_name_key UNIQUE (checklist_id, name);

-- 8. Recreate inventory view — joins through checklist_id → checklists → sets
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
LEFT JOIN public.checklists cl ON m.checklist_id = cl.id
LEFT JOIN public.sets s ON cl.set_id = s.id
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

-- ROLLBACK (complex — restoring set_id requires re-deriving from checklist→set join):
-- DROP VIEW IF EXISTS public.user_inventory_by_grade;
-- ALTER TABLE public.set_parallels DROP CONSTRAINT IF EXISTS set_parallels_checklist_id_name_key;
-- ALTER TABLE public.set_parallels ADD COLUMN set_id uuid REFERENCES public.sets(id) ON DELETE CASCADE;
-- UPDATE public.set_parallels sp SET set_id = c.set_id FROM public.checklists c WHERE c.id = sp.checklist_id;
-- ALTER TABLE public.set_parallels DROP COLUMN checklist_id;
-- ALTER TABLE public.set_parallels ADD CONSTRAINT set_parallels_set_id_name_key UNIQUE (set_id, name);
-- (then restore the original view from migration 20260405000003)
