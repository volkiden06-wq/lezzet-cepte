
-- Secure, database-side invoker for the scheduled and administrator-triggered backup.
create or replace function public.invoke_yemektadinda_cloud_backup(p_source text default 'manual')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  project_url text;
  publishable_key text;
  backup_token text;
  request_id bigint;
begin
  select decrypted_secret into project_url
  from vault.decrypted_secrets where name='yemektadinda_project_url' limit 1;
  select decrypted_secret into publishable_key
  from vault.decrypted_secrets where name='yemektadinda_publishable_key' limit 1;
  select decrypted_secret into backup_token
  from vault.decrypted_secrets where name='yemektadinda_backup_token' limit 1;

  if project_url is null or publishable_key is null or backup_token is null then
    raise exception 'YEMEK TADINDA cloud backup secrets missing in Vault';
  end if;

  select net.http_post(
    url := project_url || '/functions/v1/cloud-backup',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'apikey',publishable_key,
      'Authorization','Bearer ' || publishable_key,
      'x-backup-token',backup_token
    ),
    body := jsonb_build_object('source',coalesce(p_source,'manual')),
    timeout_milliseconds := 120000
  ) into request_id;

  return request_id;
end;
$$;

revoke all on function public.invoke_yemektadinda_cloud_backup(text) from public, anon, authenticated;
grant execute on function public.invoke_yemektadinda_cloud_backup(text) to service_role;

select cron.alter_job(
  job_id := (select jobid from cron.job where jobname='yemektadinda-daily-cloud-backup'),
  command := $$select public.invoke_yemektadinda_cloud_backup('daily-cron');$$
);
