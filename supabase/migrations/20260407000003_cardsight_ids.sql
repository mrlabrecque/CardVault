-- Add CardSight AI reference columns for import/deduplication.
-- releases and sets get UNIQUE cardsight_id (used as ON CONFLICT target for re-imports).
-- set_parallels gets a nullable cardsight_id reference (no unique constraint — parallels
--   deduplicate on (set_id, name) which already has a unique index).
-- sets also gains card_count for future collection-completion tracking.

ALTER TABLE public.releases
  ADD COLUMN IF NOT EXISTS cardsight_id TEXT UNIQUE;

ALTER TABLE public.sets
  ADD COLUMN IF NOT EXISTS cardsight_id TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS card_count   INTEGER;

ALTER TABLE public.set_parallels
  ADD COLUMN IF NOT EXISTS cardsight_id TEXT;

-- ROLLBACK:
-- ALTER TABLE public.set_parallels DROP COLUMN IF EXISTS cardsight_id;
-- ALTER TABLE public.sets DROP COLUMN IF EXISTS card_count;
-- ALTER TABLE public.sets DROP COLUMN IF EXISTS cardsight_id;
-- ALTER TABLE public.releases DROP COLUMN IF EXISTS cardsight_id;
