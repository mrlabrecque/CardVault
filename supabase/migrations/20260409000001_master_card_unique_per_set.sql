-- Add a unique constraint on (set_id, player, card_number) so that
-- CardSight photo/variation duplicates collapse to a single row per card.
-- card_number is nullable so we use a partial index covering non-null numbers
-- plus a separate partial index for null card_numbers (one per player per set).

CREATE UNIQUE INDEX IF NOT EXISTS master_card_definitions_set_player_number_uq
  ON public.master_card_definitions (set_id, player, card_number)
  WHERE card_number IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS master_card_definitions_set_player_null_number_uq
  ON public.master_card_definitions (set_id, player)
  WHERE card_number IS NULL;

-- ROLLBACK:
-- DROP INDEX IF EXISTS public.master_card_definitions_set_player_null_number_uq;
-- DROP INDEX IF EXISTS public.master_card_definitions_set_player_number_uq;
