-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- Cards table
create table cards (
  id uuid primary key default uuid_generate_v4(),
  owner_id uuid references auth.users(id) on delete cascade not null,
  player text not null,
  sport text,
  set_name text,
  year integer,
  variant text,
  grade text,
  price_paid decimal(10,2),
  current_value decimal(10,2),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Lookup history table
create table lookup_history (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id) on delete cascade not null,
  query text not null,
  results jsonb default '[]',
  timestamp timestamptz default now()
);

-- Wishlist table
create table wishlist (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id) on delete cascade not null,
  card_details jsonb not null,
  target_price decimal(10,2),
  alert_status text default 'active' check (alert_status in ('active', 'triggered', 'paused')),
  created_at timestamptz default now()
);

-- Row Level Security
alter table cards enable row level security;
alter table lookup_history enable row level security;
alter table wishlist enable row level security;

create policy "Users can only access their own cards"
  on cards for all using (auth.uid() = owner_id);

create policy "Users can only access their own lookup history"
  on lookup_history for all using (auth.uid() = user_id);

create policy "Users can only access their own wishlist"
  on wishlist for all using (auth.uid() = user_id);

-- Updated_at trigger for cards
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger cards_updated_at
  before update on cards
  for each row execute function update_updated_at();
