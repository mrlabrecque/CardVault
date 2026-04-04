create table if not exists public.sets (
  id               uuid        primary key default gen_random_uuid(),
  name             text        not null,
  year             integer     not null check (year > 1900),
  sport            text        not null check (sport in ('Basketball', 'Baseball', 'Football', 'Soccer')),
  release_type     text        not null,
  ebay_search_template text,
  set_slug         text        not null unique,
  created_at       timestamptz default now()
);

alter table public.sets enable row level security;

-- All authenticated users can read sets
create policy "Authenticated users can read sets"
  on public.sets for select
  to authenticated
  using (true);

-- Only app admins can insert
create policy "App admins can insert sets"
  on public.sets for insert
  to authenticated
  with check (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and is_app_admin = true
    )
  );

-- Only app admins can update
create policy "App admins can update sets"
  on public.sets for update
  to authenticated
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and is_app_admin = true
    )
  );

-- Only app admins can delete
create policy "App admins can delete sets"
  on public.sets for delete
  to authenticated
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and is_app_admin = true
    )
  );
