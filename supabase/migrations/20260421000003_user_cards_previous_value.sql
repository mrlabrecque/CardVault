alter table user_cards
  add column if not exists previous_value numeric(10, 2);
