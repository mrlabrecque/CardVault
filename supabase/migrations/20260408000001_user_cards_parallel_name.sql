-- Add parallel_name as a denormalized display field on user_cards.
-- Stores the parallel's display name at save time so it's always readable
-- even when parallel_id is null (e.g. "Other…" free-text entry).
-- On load, prefer set_parallels.name (via join); fall back to this column.

ALTER TABLE public.user_cards
  ADD COLUMN IF NOT EXISTS parallel_name text NOT NULL DEFAULT 'Base';
