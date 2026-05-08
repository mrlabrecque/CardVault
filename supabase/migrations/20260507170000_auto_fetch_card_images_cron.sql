-- Schedule auto-fetch-card-images to backfill missing master_card_definitions.image_url (Vault auth, same pattern as market-movers).

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
  where jobname = 'auto-fetch-card-images'
  limit 1;

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;
end $$;

-- Daily 03:30 UTC — adjust if needed.
select cron.schedule(
  'auto-fetch-card-images',
  '30 3 * * *',
  $$
  select net.http_post(
    url := 'https://bqwfyxthnoxcbvgchbyh.supabase.co/functions/v1/auto-fetch-card-images',
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
