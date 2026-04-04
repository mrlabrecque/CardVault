-- User profiles: extends auth.users with app-level settings
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  is_app_admin boolean not null default false,
  created_at   timestamptz default now()
);

alter table public.profiles enable row level security;

-- Users can read their own profile (needed to check isAppAdmin on the frontend)
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

-- is_app_admin must be set manually in the Supabase dashboard / service role only.
-- No update policy is granted here so users cannot elevate themselves.

-- Auto-create a profile row whenever a new user signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
