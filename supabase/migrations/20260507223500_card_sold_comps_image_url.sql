-- Add optional thumbnail URL for sold comps rows.
ALTER TABLE public.card_sold_comps
  ADD COLUMN IF NOT EXISTS image_url TEXT;

