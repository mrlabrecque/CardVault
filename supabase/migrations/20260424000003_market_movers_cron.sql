-- Schedule market-movers-refresh to run weekly on Sunday at 2 AM UTC
-- pg_cron + pg_net extensions must already be enabled
select cron.schedule(
  'market-movers-refresh',
  '0 2 * * 0',   -- every Sunday at 2 AM UTC
  $$
  select net.http_post(
    url     := 'https://bqwfyxthnoxcbvgchbyh.supabase.co/functions/v1/market-movers-refresh',
    headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJxd2Z5eHRobm94Y2J2Z2NoYnloIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTMxMDgwMywiZXhwIjoyMDkwODg2ODAzfQ.IsJQ8rgvVjXP3sYwQGe1mZWlWMD0k6WZx7LD7BlC8Sw"}'::jsonb,
    body    := '{}'::jsonb
  );
  $$
);
