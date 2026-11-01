-- YEMEK TADINDA: otomatik yeni sipariş Web Push bildirimi
-- Mevcut sipariş/ürün kayıtlarını silmez veya değiştirmez.
-- Bu scripti Supabase SQL Editor'de bir kez çalıştırın.

-- Supabase Vault'a Edge Function ile ortak gizli tetikleyici anahtarını kaydet.
select vault.create_secret('066eF4WyT-GtIikPpLW_9wUegENobyWVQexkUkTV4Ek', 'order_push_hook_secret', 'Yalnızca orders INSERT tetikleyicisinin kullandığı gizli anahtar');

create or replace function public.notify_new_order_push()
returns trigger
language plpgsql
security definer
set search_path = public, net, vault
as $$
declare
  hook_secret text;
begin
  select decrypted_secret
    into hook_secret
    from vault.decrypted_secrets
   where name = 'order_push_hook_secret'
   order by created_at desc
   limit 1;

  if hook_secret is null or hook_secret = '' then
    raise warning 'YEMEK TADINDA push hook secret bulunamadı';
    return new;
  end if;

  perform net.http_post(
    url := 'https://jlpqdjhxdpmighnpebkj.supabase.co/functions/v1/send-notification',
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

-- Kontrol: trigger kuruldu mu?
select trigger_name, event_manipulation, event_object_table
from information_schema.triggers
where trigger_name = 'trg_notify_new_order_push';
