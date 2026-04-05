-- Stores eBay sold comps fetched for a specific user card instance.
-- Refreshed on each "Get Market Value" call — old rows are replaced.

CREATE TABLE card_sold_comps (
  id            uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  user_card_id  uuid        REFERENCES user_cards(id) ON DELETE CASCADE NOT NULL,
  ebay_item_id  text,
  title         text        NOT NULL,
  price         numeric     NOT NULL,
  currency      text        NOT NULL DEFAULT 'USD',
  -- 'auction' | 'fixed_price' | 'best_offer'
  -- best_offer price is the listing ask, not the accepted offer amount
  sale_type     text        NOT NULL CHECK (sale_type IN ('auction', 'fixed_price', 'best_offer')),
  sold_at       timestamptz,
  url           text,
  fetched_at    timestamptz NOT NULL DEFAULT NOW()
);

ALTER TABLE card_sold_comps ENABLE ROW LEVEL SECURITY;

-- Users may only see comps that belong to their own cards
CREATE POLICY "users_select_own_card_comps" ON card_sold_comps
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM user_cards
      WHERE user_cards.id  = card_sold_comps.user_card_id
        AND user_cards.user_id = auth.uid()
    )
  );

-- Backend inserts via service-role key bypass RLS, but add an
-- authenticated insert policy so direct Supabase calls also work.
CREATE POLICY "users_insert_own_card_comps" ON card_sold_comps
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_cards
      WHERE user_cards.id  = card_sold_comps.user_card_id
        AND user_cards.user_id = auth.uid()
    )
  );

CREATE POLICY "users_delete_own_card_comps" ON card_sold_comps
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM user_cards
      WHERE user_cards.id  = card_sold_comps.user_card_id
        AND user_cards.user_id = auth.uid()
    )
  );

CREATE INDEX card_sold_comps_user_card_id_idx ON card_sold_comps(user_card_id);
