-- Add set_id FK to user_cards so import rows (master_card_id = null)
-- can still resolve their release and ebay_search_template.
-- Nullable: existing linked cards don't need it (they resolve via master_card_definitions → sets).

ALTER TABLE public.user_cards
  ADD COLUMN IF NOT EXISTS set_id uuid REFERENCES public.sets(id) ON DELETE SET NULL;
