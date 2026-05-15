-- Ensure every set that already has parallels also has a literal `set_parallels` row named `Base`,
-- then repoint the catalog “default” variant (`master_card_definitions`) for each `set_card`
-- to that parallel — same ordering as `set_card_base_variants` / `_default_parallel_for_set`.
--
-- Idempotent: safe to re-run. Skips sets that already have a parallel whose lower(trim(name)) = 'base'.
-- Skips `UPDATE master_card_definitions` when a different row already holds (set_card_id, Base).

-- 1) Insert Base parallel where missing (sort before existing rows so legacy data stays consistent).
INSERT INTO public.set_parallels (set_id, name, serial_max, is_auto, sort_order)
SELECT
  s.id,
  'Base',
  NULL,
  false,
  COALESCE(
    (SELECT MIN(sp.sort_order) FROM public.set_parallels sp WHERE sp.set_id = s.id),
    0
  ) - 1
FROM public.sets s
WHERE EXISTS (SELECT 1 FROM public.set_parallels sp WHERE sp.set_id = s.id)
  AND NOT EXISTS (
    SELECT 1
    FROM public.set_parallels sp2
    WHERE sp2.set_id = s.id
      AND lower(trim(sp2.name)) = 'base'
  )
ON CONFLICT (set_id, name) DO NOTHING;

-- 2) Repoint the canonical default master row per set_card to the Base parallel (when not already).
WITH base_parallel AS (
  SELECT sp.set_id, sp.id AS base_id
  FROM public.set_parallels sp
  WHERE lower(trim(sp.name)) = 'base'
),
canon AS (
  SELECT DISTINCT ON (m.set_card_id)
    m.id AS master_id,
    bp.base_id
  FROM public.master_card_definitions m
  INNER JOIN public.set_cards sc ON sc.id = m.set_card_id
  INNER JOIN public.set_parallels p ON p.id = m.parallel_id AND p.set_id = sc.set_id
  INNER JOIN base_parallel bp ON bp.set_id = sc.set_id
  ORDER BY
    m.set_card_id,
    CASE WHEN lower(trim(p.name)) = 'base' THEN 0 ELSE 1 END,
    p.sort_order NULLS LAST,
    p.name
)
UPDATE public.master_card_definitions m
SET parallel_id = c.base_id
FROM canon c
WHERE m.id = c.master_id
  AND m.parallel_id IS DISTINCT FROM c.base_id
  AND NOT EXISTS (
    SELECT 1
    FROM public.master_card_definitions x
    WHERE x.set_card_id = m.set_card_id
      AND x.parallel_id = c.base_id
      AND x.id <> m.id
  );

-- 3) Denormalized copy on owned cards: keep in sync with the master variant’s parallel.
UPDATE public.user_cards uc
SET
  parallel_id = m.parallel_id,
  parallel_name = p.name
FROM public.master_card_definitions m
INNER JOIN public.set_parallels p ON p.id = m.parallel_id
WHERE uc.master_card_id = m.id
  AND uc.master_card_id IS NOT NULL
  AND (
    uc.parallel_id IS DISTINCT FROM m.parallel_id
    OR lower(trim(coalesce(uc.parallel_name, ''))) IS DISTINCT FROM lower(trim(p.name))
  );
