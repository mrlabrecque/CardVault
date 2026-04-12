-- Removes ALL CSV-imported cards and associated import-source records.
-- Scoped to source='import' only — CardSight and manually-added data is untouched.
-- Safe to re-run.

-- Step 1: Delete user_cards that belong to import sets (Option A rows: set_id set, master_card_id null)
DELETE FROM public.user_cards
WHERE set_id IN (SELECT id FROM public.sets WHERE source = 'import');

-- Step 2: Delete any legacy user_cards linked via master_card_id to import sets
--         (pre-Option A rows that may have been inserted during early testing)
DELETE FROM public.user_cards uc
USING public.master_card_definitions m
JOIN public.sets s ON m.set_id = s.id
WHERE uc.master_card_id = m.id
  AND s.source = 'import';

-- Step 3: Delete master_card_definitions in import sets (legacy catalog pollution)
DELETE FROM public.master_card_definitions
WHERE set_id IN (SELECT id FROM public.sets WHERE source = 'import');

-- Step 4: Delete import sets
DELETE FROM public.sets WHERE source = 'import';

-- Step 5: Delete import releases (cascades are off, so only delete if no sets remain)
DELETE FROM public.releases WHERE source = 'import';
