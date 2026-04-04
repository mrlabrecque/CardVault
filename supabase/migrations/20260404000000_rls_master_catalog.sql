-- Master card definitions: public catalog, read-only for all authenticated users
create table if not exists public.master_card_definitions (
  id          uuid primary key default uuid_generate_v4(),
  player      text not null,
  sport       text,
  set_name    text,
  year        integer,
  variant     text,
  created_at  timestamptz default now()
);

alter table public.master_card_definitions enable row level security;

-- Anyone (authenticated or anon) can read the catalog; no one can write via the API
create policy "Catalog is public read-only"
  on public.master_card_definitions
  for select
  using (true);
