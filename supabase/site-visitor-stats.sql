-- YEMEK TADINDA - Günlük tekil web sitesi ziyaretçi sayacı
-- Bu dosya mevcut sipariş, ürün veya müşteri tablolarını değiştirmez.

create table if not exists public.site_daily_visitors (
  visit_date date not null,
  visitor_id uuid not null,
  created_at timestamptz not null default now(),
  constraint site_daily_visitors_pkey primary key (visit_date, visitor_id)
);

alter table public.site_daily_visitors enable row level security;

-- Ziyaretçi kimlikleri doğrudan okunamaz veya tabloya doğrudan yazılamaz.
revoke all on table public.site_daily_visitors from anon, authenticated;

-- Her anonim tarayıcı için günde en fazla bir kayıt oluşturur.
create or replace function public.record_site_visit(p_visitor_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_visitor_id is null then
    return;
  end if;

  insert into public.site_daily_visitors (visit_date, visitor_id)
  values ((timezone('Europe/Istanbul', now()))::date, p_visitor_id)
  on conflict (visit_date, visitor_id) do nothing;
end;
$$;

revoke all on function public.record_site_visit(uuid) from public;
grant execute on function public.record_site_visit(uuid) to anon, authenticated;

-- Son 7 günün (istenirse en fazla 90 gün) günlük tekil ziyaretçi sayılarını
-- yalnızca yönetici oturumu olan kullanıcıya döndürür.
create or replace function public.get_site_visitor_stats(p_days integer default 7)
returns table (visit_date date, visitors bigint)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_today date := (timezone('Europe/Istanbul', now()))::date;
  v_days integer := least(greatest(coalesce(p_days, 7), 1), 90);
  v_start date;
begin
  if coalesce(public.is_admin(), false) is not true then
    raise exception 'Bu istatistikleri görüntüleme yetkiniz yok.'
      using errcode = '42501';
  end if;

  v_start := v_today - (v_days - 1);

  return query
  select
    calendar.day::date,
    coalesce(stats.visitors, 0)::bigint
  from generate_series(
    v_start::timestamp,
    v_today::timestamp,
    interval '1 day'
  ) as calendar(day)
  left join (
    select d.visit_date, count(*)::bigint as visitors
    from public.site_daily_visitors as d
    where d.visit_date between v_start and v_today
    group by d.visit_date
  ) as stats
    on stats.visit_date = calendar.day::date
  order by calendar.day::date;
end;
$$;

revoke all on function public.get_site_visitor_stats(integer) from public;
grant execute on function public.get_site_visitor_stats(integer) to authenticated;
