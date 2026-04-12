-- Add source column to releases and sets to distinguish how records were created.
-- 'cardsight' = imported via CardSight admin flow (has cardsight_id)
-- 'import'    = created by the CSV collection importer (no cardsight_id yet)
-- 'manual'    = created manually by admin (no cardsight_id)

ALTER TABLE public.releases
  ADD COLUMN source text NOT NULL DEFAULT 'cardsight'
    CHECK (source IN ('cardsight', 'import', 'manual'));

ALTER TABLE public.sets
  ADD COLUMN source text NOT NULL DEFAULT 'cardsight'
    CHECK (source IN ('cardsight', 'import', 'manual'));

-- Existing records with a cardsight_id are 'cardsight'; those without are 'manual'
UPDATE public.releases SET source = 'manual' WHERE cardsight_id IS NULL;
UPDATE public.sets      SET source = 'manual' WHERE cardsight_id IS NULL;

-- ROLLBACK:
-- ALTER TABLE public.sets DROP COLUMN source;
-- ALTER TABLE public.releases DROP COLUMN source;
