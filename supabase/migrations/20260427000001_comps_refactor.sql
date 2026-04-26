-- Refactor card_sold_comps to be master_card + parallel identity instead of per-user_card

-- 1. Add new columns
ALTER TABLE card_sold_comps
  ADD COLUMN master_card_id UUID REFERENCES master_card_definitions(id) ON DELETE CASCADE,
  ADD COLUMN parallel_name TEXT,
  ADD COLUMN grade TEXT;

-- 2. Back-fill master_card_id + parallel_name from user_cards for existing rows
UPDATE card_sold_comps csc
SET
  master_card_id = uc.master_card_id,
  parallel_name = uc.parallel_name
FROM user_cards uc
WHERE csc.user_card_id = uc.id
  AND uc.master_card_id IS NOT NULL;

-- 3. Make user_card_id nullable (comps are now owned by master card)
ALTER TABLE card_sold_comps ALTER COLUMN user_card_id DROP NOT NULL;

-- 4. Add index for the new primary lookup pattern
CREATE INDEX idx_card_sold_comps_master ON card_sold_comps(master_card_id, parallel_name);

-- 5. Update RLS
DROP POLICY IF EXISTS "Users can read own card comps" ON card_sold_comps;

-- Any authenticated user can read catalog comps (master_card_id set)
CREATE POLICY "Auth users read catalog comps"
  ON card_sold_comps FOR SELECT TO authenticated
  USING (master_card_id IS NOT NULL);

-- Users can read their own user-card comps (legacy rows)
CREATE POLICY "Users read own card comps"
  ON card_sold_comps FOR SELECT TO authenticated
  USING (
    user_card_id IN (
      SELECT id FROM user_cards WHERE user_id = auth.uid()
    )
  );
