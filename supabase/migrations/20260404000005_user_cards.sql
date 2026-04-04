-- Extend master_card_definitions with card-specific fields
ALTER TABLE public.master_card_definitions
  ADD COLUMN IF NOT EXISTS set_id       uuid references public.sets(id),
  ADD COLUMN IF NOT EXISTS card_number  text,
  ADD COLUMN IF NOT EXISTS parallel_type text default 'Base',
  ADD COLUMN IF NOT EXISTS is_rookie    boolean default false,
  ADD COLUMN IF NOT EXISTS is_auto      boolean default false,
  ADD COLUMN IF NOT EXISTS is_patch     boolean default false,
  ADD COLUMN IF NOT EXISTS is_ssp       boolean default false,
  ADD COLUMN IF NOT EXISTS serial_max   integer;

-- Allow authenticated users to contribute new card definitions (crowdsourced catalog)
CREATE POLICY "Authenticated users can add to master catalog"
  ON public.master_card_definitions
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- User-specific card instances (one per physical card owned)
CREATE TABLE IF NOT EXISTS public.user_cards (
  id             uuid primary key default uuid_generate_v4(),
  user_id        uuid references auth.users(id) on delete cascade not null,
  master_card_id uuid references public.master_card_definitions(id) on delete restrict not null,
  price_paid     decimal(10,2),
  serial_number  text,
  current_value  decimal(10,2),
  is_graded      boolean default false,
  grader         text,
  grade_value    text,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);

ALTER TABLE public.user_cards enable row level security;

CREATE POLICY "Users can only access their own user_cards"
  ON public.user_cards FOR ALL USING (auth.uid() = user_id);

CREATE TRIGGER user_cards_updated_at
  BEFORE UPDATE ON public.user_cards
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
