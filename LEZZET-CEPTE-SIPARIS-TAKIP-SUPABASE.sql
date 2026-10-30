-- LEZZET CEPTE - Sipariş takip düzeltmesi
-- Mevcut public.orders tablosundaki sütunları kullanır:
-- order_number, customer_name, customer_phone, customer_address,
-- items, total, payment_method, status, notes, created_at

create or replace function public.lookup_order(
  p_order_number text,
  p_phone text
)
returns table (
  order_number text,
  status text,
  total numeric,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.order_number::text,
    o.status::text,
    o.total::numeric,
    o.created_at
  from public.orders o
  where
    length(regexp_replace(upper(coalesce(p_order_number, '')), '[^A-Z0-9]', '', 'g')) >= 5
    and regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') =
        regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')
    and (
      regexp_replace(upper(coalesce(o.order_number, '')), '[^A-Z0-9]', '', 'g') =
      regexp_replace(upper(coalesce(p_order_number, '')), '[^A-Z0-9]', '', 'g')
      or right(
        regexp_replace(upper(coalesce(o.order_number, '')), '[^A-Z0-9]', '', 'g'),
        length(regexp_replace(upper(coalesce(p_order_number, '')), '[^A-Z0-9]', '', 'g'))
      ) = regexp_replace(upper(coalesce(p_order_number, '')), '[^A-Z0-9]', '', 'g')
    )
  order by o.created_at desc
  limit 1;
$$;

create or replace function public.lookup_orders_by_phone(p_phone text)
returns table (
  order_number text,
  status text,
  total numeric,
  created_at timestamptz,
  payment_method text,
  items jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    o.order_number::text,
    o.status::text,
    o.total::numeric,
    o.created_at,
    o.payment_method::text,
    o.items
  from public.orders o
  where
    length(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')) >= 10
    and regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') =
        regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')
  order by o.created_at desc;
$$;

revoke all on function public.lookup_order(text, text) from public;
revoke all on function public.lookup_orders_by_phone(text) from public;
grant usage on schema public to anon, authenticated;
grant execute on function public.lookup_order(text, text) to anon, authenticated;
grant execute on function public.lookup_orders_by_phone(text) to anon, authenticated;

notify pgrst, 'reload schema';
