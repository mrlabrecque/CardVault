-- Remove old RPC name if an earlier revision created it (app now calls portfolio_movers_from_vault).
DROP FUNCTION IF EXISTS public.market_movers_from_vault(text);
