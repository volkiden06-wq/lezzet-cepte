-- Kampanya/duyuru bildirimi abone sayısını yalnızca yöneticilere gösterir.
-- push_subscriptions tablosunu veya kayıtlarını değiştirmez.
create or replace function public.get_push_subscription_count()
returns table (subscriber_count bigint)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(public.is_admin(), false) is not true then
    raise exception 'Bu bilgiyi görüntüleme yetkiniz yok.'
      using errcode = '42501';
  end if;

  return query
  select count(*)::bigint
  from public.push_subscriptions;
end;
$$;

revoke all on function public.get_push_subscription_count() from public;
grant execute on function public.get_push_subscription_count() to authenticated;
