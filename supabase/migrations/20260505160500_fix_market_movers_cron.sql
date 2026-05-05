-- Fix market-movers-refresh scheduling using pg_cron + pg_net + Vault secret.
-- This replaces any previous schedule that used a hardcoded/expired JWT.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$
declare
  existing_job_id bigint;
begin
  select jobid
    into existing_job_id
  from cron.job
  where jobname = 'market-movers-refresh'
  limit 1;

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;
end $$;

-- Every Monday at 2 AM UTC.
select cron.schedule(
  'market-movers-refresh',
  '0 2 * * 1',
  $$
  select net.http_post(
    url := 'https://bqwfyxthnoxcbvgchbyh.supabase.co/functions/v1/market-movers-refresh',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'service_role_key'
        limit 1
      )
    ),
    body := '{}'::jsonb
  ) as request_id;
  $$
);
