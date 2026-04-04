-- Allow users to self-create their own profile row.
-- The WITH CHECK ensures is_app_admin cannot be set to true via the client.
create policy "Users can create own profile"
  on public.profiles for insert
  with check (auth.uid() = id and is_app_admin = false);
