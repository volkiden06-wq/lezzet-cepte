-- YEMEK TADINDA: every new order sends a Web Push alert.
-- Run once in Supabase SQL Editor. Requires pg_net and Vault extensions.
-- Replace the placeholder below with the SAME ORDER_PUSH_HOOK_SECRET
-- saved in Supabase Edge Function Secrets.

select vault.create_secret(
  'REPLACE_WITH_SECRET_IN_SUPABASE_ONLY',
  'order_push_hook_secret',
  'Private key used by YEMEK TADINDA new-order push trigger'
);

create or replace function public.notify_new_order_push()
returns trigger
language plpgsql
security definer
set search_path = public, net, vault
as $$
declare
  hook_secret text;
begin
  select decrypted_secret into hook_secret
  from vault.decrypted_secrets
  where name = 'order_push_hook_secret'
  order by created_at desc
  limit 1;

  if hook_secret is null or hook_secret = '' then
    raise warning 'order_push_hook_secret missing; push skipped';
    return new;
  end if;

  perform net.http_post(
    url := 'https://jlpqdjhxdpmighnpebkj.supabase.co/functions/v1/send-order-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-order-hook-secret', hook_secret
    ),
    body := jsonb_build_object(
      'type', 'order',
      'record', jsonb_build_object(
        'order_number', new.order_number,
        'customer_name', new.customer_name,
        'total', new.total
      )
    ),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_new_order_push on public.orders;
create trigger trg_notify_new_order_push
after insert on public.orders
for each row
execute function public.notify_new_order_push();

select trigger_name, event_manipulation, event_object_table
from information_schema.triggers
where trigger_name = 'trg_notify_new_order_push';
