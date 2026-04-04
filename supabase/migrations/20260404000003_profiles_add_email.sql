alter table public.profiles
  add column if not exists email text;

-- Allow users to update only their own email (not is_app_admin)
create policy "Users can update own email"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id and is_app_admin = (select is_app_admin from public.profiles where id = auth.uid()));

-- Keep email in sync when a new user is created via the trigger
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;
