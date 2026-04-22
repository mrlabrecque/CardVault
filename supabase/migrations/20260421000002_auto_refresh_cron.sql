-- Enable required extensions (safe to run even if already enabled)
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net  with schema extensions;

-- Remove existing schedule if re-running
select cron.unschedule('auto-refresh-cards') where exists (
  select 1 from cron.job where jobname = 'auto-refresh-cards'
);

-- Schedule every 4 hours.
-- Replace <your-service-role-key> with the key from Supabase dashboard → Project Settings → API.
select cron.schedule(
  'auto-refresh-cards',
  '0 */4 * * *',
  $$
  select net.http_post(
    url     := 'https://bqwfyxthnoxcbvgchbyh.supabase.co/functions/v1/auto-refresh-cards',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer <your-service-role-key>"}'::jsonb,
    body    := '{}'::jsonb
  ) as request_id;
  $$
);
