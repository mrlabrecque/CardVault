-- Legacy schedule migration.
-- Do not hardcode service-role JWTs in SQL.
-- Superseded by 20260505160500_fix_market_movers_cron.sql.

-- Schedule market-movers-refresh to run weekly on Sunday at 2 AM UTC
-- pg_cron + pg_net extensions must already be enabled
select cron.schedule(
  'market-movers-refresh',
  '0 2 * * 0',   -- every Sunday at 2 AM UTC
  $$
  select net.http_post(
    url     := 'https://bqwfyxthnoxcbvgchbyh.supabase.co/functions/v1/market-movers-refresh',
    headers := '{"Content-Type":"application/json","Authorization":"Bearer <set-via-vault-not-literal-token>"}'::jsonb,
    body    := '{}'::jsonb
  );
  $$
);
