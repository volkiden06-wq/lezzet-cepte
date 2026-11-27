-- Yemek Tadinda: server-side daily spin wheel (STAGING/BRANCH ONLY)
-- Run only after reviewing auth requirements and testing in an isolated Supabase project.
-- This schema requires authenticated Supabase users. It does not touch existing order tables.

create table if not exists public.daily_spin_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  spin_date date not null default (timezone('Europe/Istanbul', now())::date),
  prize_code text not null,
  prize_label text not null,
  prize_value integer not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, spin_date)
);

alter table public.daily_spin_results enable row level security;
revoke all on public.daily_spin_results from anon, authenticated;
-- No direct client read/write policies. Access is via SECURITY DEFINER RPC only.

create or replace function public.spin_daily_wheel()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_date date := (timezone('Europe/Istanbul', now())::date);
  v_pick integer;
  v_code text;
  v_label text;
  v_value integer;
  v_result public.daily_spin_results%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  -- Idempotent daily limit: if already spun, return that day's record.
  select * into v_result
  from public.daily_spin_results
  where user_id = v_uid and spin_date = v_date;

  if found then
    return jsonb_build_object(
      'already_spun', true, 'date', v_result.spin_date,
      'prize_code', v_result.prize_code, 'prize_label', v_result.prize_label,
      'prize_value', v_result.prize_value
    );
  end if;

  -- Equal probability across six slots; the outcome is server-generated.
  v_pick := floor(random() * 6)::integer;
  case v_pick
    when 0 then v_code := 'discount_5'; v_label := '%5 İNDİRİM'; v_value := 5;
    when 1 then v_code := 'drink'; v_label := 'ÜCRETSİZ İÇECEK'; v_value := 0;
    when 2 then v_code := 'discount_10'; v_label := '%10 İNDİRİM'; v_value := 10;
    when 3 then v_code := 'dessert'; v_label := 'ÜCRETSİZ TATLI'; v_value := 0;
    when 4 then v_code := 'discount_15'; v_label := '%15 İNDİRİM'; v_value := 15;
    else v_code := 'no_prize'; v_label := 'ŞANS YOK'; v_value := 0;
  end case;

  insert into public.daily_spin_results(user_id, spin_date, prize_code, prize_label, prize_value)
  values (v_uid, v_date, v_code, v_label, v_value)
  on conflict (user_id, spin_date) do nothing
  returning * into v_result;

  -- Handles concurrent requests: return the single stored result.
  if v_result.id is null then
    select * into v_result from public.daily_spin_results
    where user_id = v_uid and spin_date = v_date;
  end if;

  return jsonb_build_object(
    'already_spun', false, 'date', v_result.spin_date,
    'prize_code', v_result.prize_code, 'prize_label', v_result.prize_label,
    'prize_value', v_result.prize_value
  );
end;
$$;

revoke all on function public.spin_daily_wheel() from public, anon;
grant execute on function public.spin_daily_wheel() to authenticated;
