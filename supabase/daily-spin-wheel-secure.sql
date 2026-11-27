-- Yemek Tadinda daily wheel - phone + existing order verification, isolated branch only.
-- Review and apply only in a staging Supabase project first.
create table if not exists public.daily_spin_results (
 id uuid primary key default gen_random_uuid(),
 phone_digits text not null check(length(phone_digits) between 10 and 15),
 spin_date date not null default (timezone('Europe/Istanbul',now())::date),
 verification_order text not null,
 prize_code text not null,
 prize_label text not null,
 prize_value integer not null default 0,
 redeemed_at timestamptz,
 created_at timestamptz not null default now(),
 unique(phone_digits,spin_date)
);
alter table public.daily_spin_results enable row level security;
revoke all on public.daily_spin_results from anon,authenticated;
-- phone + order pairing must exist in orders. Outcome is server-selected and daily limit atomic.
create or replace function public.spin_daily_wheel(p_phone text,p_order_number text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_phone text:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
 v_order text:=upper(trim(coalesce(p_order_number,'')));
 v_date date:=(timezone('Europe/Istanbul',now())::date);
 v_pick integer; v_code text; v_label text; v_value integer;
 v_result public.daily_spin_results%rowtype;
begin
 if length(v_phone) not between 10 and 15 or length(v_order)<5 then raise exception 'Telefon veya sipariş numarası geçersiz'; end if;
 if not exists(select 1 from public.orders o where upper(trim(coalesce(o.order_number,'')))=v_order and regexp_replace(coalesce(o.customer_phone,''),'[^0-9]','','g')=v_phone) then raise exception 'Telefon ve sipariş numarası eşleşmiyor'; end if;
 select * into v_result from public.daily_spin_results where phone_digits=v_phone and spin_date=v_date;
 if found then return jsonb_build_object('already_spun',true,'date',v_date,'prize_code',v_result.prize_code,'prize_label',v_result.prize_label,'prize_value',v_result.prize_value,'redeemed',v_result.redeemed_at is not null); end if;
 v_pick:=floor(random()*6)::integer;
 case v_pick
 when 0 then v_code:='discount_5';v_label:='%5 İNDİRİM';v_value:=5;
 when 1 then v_code:='drink';v_label:='ÜCRETSİZ İÇECEK';v_value:=0;
 when 2 then v_code:='discount_10';v_label:='%10 İNDİRİM';v_value:=10;
 when 3 then v_code:='dessert';v_label:='ÜCRETSİZ TATLI';v_value:=0;
 when 4 then v_code:='discount_15';v_label:='%15 İNDİRİM';v_value:=15;
 else v_code:='no_prize';v_label:='ŞANS YOK';v_value:=0;
 end case;
 insert into public.daily_spin_results(phone_digits,spin_date,verification_order,prize_code,prize_label,prize_value)
 values(v_phone,v_date,v_order,v_code,v_label,v_value) on conflict(phone_digits,spin_date) do nothing;
 select * into v_result from public.daily_spin_results where phone_digits=v_phone and spin_date=v_date;
 return jsonb_build_object('already_spun',false,'date',v_date,'prize_code',v_result.prize_code,'prize_label',v_result.prize_label,'prize_value',v_result.prize_value,'redeemed',false);
end $$;
revoke all on function public.spin_daily_wheel(text,text) from public;
grant execute on function public.spin_daily_wheel(text,text) to anon,authenticated;
-- Admin-only retrieval; existing is_admin() authorization.
create or replace function public.admin_daily_spin_results()
returns table(spin_date date,phone_digits text,prize_label text,prize_value integer,redeemed_at timestamptz,created_at timestamptz)
language plpgsql security definer set search_path=''
as $$ begin
 if not public.is_admin() then raise exception 'Yönetici yetkisi gerekli'; end if;
 return query select r.spin_date,r.phone_digits,r.prize_label,r.prize_value,r.redeemed_at,r.created_at from public.daily_spin_results r order by r.created_at desc;
end $$;
revoke all on function public.admin_daily_spin_results() from public,anon;
grant execute on function public.admin_daily_spin_results() to authenticated;
