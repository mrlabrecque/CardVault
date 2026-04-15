create table wishlist_matches (
  id            uuid primary key default uuid_generate_v4(),
  wishlist_id   uuid not null references wishlist(id) on delete cascade,
  ebay_item_id  text,
  title         text not null,
  price         decimal(10,2) not null,
  listing_type  text not null check (listing_type in ('AUCTION', 'FIXED_PRICE')),
  url           text,
  image_url     text,
  found_at      timestamptz not null default now()
);

create index wishlist_matches_wishlist_id_idx on wishlist_matches(wishlist_id);

alter table wishlist_matches enable row level security;

-- Users can only see matches for their own wishlist items
create policy "Users can read their own wishlist matches"
  on wishlist_matches for select
  using (
    exists (
      select 1 from wishlist w
      where w.id = wishlist_id and w.user_id = auth.uid()
    )
  );
