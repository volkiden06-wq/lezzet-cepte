-- YEMEK TADINDA: transactional customer loyalty redemption at checkout.
-- The database migration has already been applied in the production Supabase project.
-- Existing order notification and push triggers are intentionally preserved.

alter table public.orders
  add column if not exists subtotal numeric,
  add column if not exists discount_amount numeric not null default 0 check (discount_amount >= 0),
  add column if not exists points_redeemed integer not null default 0 check (points_redeemed >= 0);

create unique index if not exists loyalty_transactions_one_redeem_per_order
  on public.loyalty_transactions(order_number)
  where transaction_type = 'redeem' and order_number is not null;

drop policy if exists "Public can submit orders" on public.orders;
create policy "Public can submit orders"
on public.orders
for insert
to anon, authenticated
with check (
  customer_name is not null
  and length(trim(customer_name)) >= 2
  and length(trim(customer_name)) <= 120
  and customer_phone is not null
  and length(regexp_replace(customer_phone, '\D', '', 'g')) between 10 and 15
  and jsonb_typeof(items) = 'array'
  and total >= 0
  and payment_method in ('Kapıda Nakit', 'Kapıda Kredi Kartı')
  and status = 'Yeni'
  and coalesce(discount_amount, 0) = 0
  and coalesce(points_redeemed, 0) = 0
);

create or replace function public.create_customer_order_with_points(
  p_order_number text,
  p_customer_name text,
  p_customer_phone text,
  p_customer_address text,
  p_items jsonb,
  p_subtotal numeric,
  p_payment_method text,
  p_notes text,
  p_points_to_use integer default 0,
  p_verification_order_number text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_phone text := regexp_replace(coalesce(p_customer_phone, ''), '[^0-9]', '', 'g');
  v_old_order text := upper(trim(coalesce(p_verification_order_number, '')));
  v_order text := upper(trim(coalesce(p_order_number, '')));
  v_name text := left(trim(coalesce(p_customer_name, '')), 120);
  v_address text := trim(coalesce(p_customer_address, ''));
  v_notes text := left(coalesce(p_notes, ''), 2000);
  v_items_subtotal numeric(12,2);
  v_points_balance integer := 0;
  v_remaining_points integer := 0;
  v_discount numeric(12,2) := 0;
  v_total numeric(12,2);
  v_points integer := greatest(coalesce(p_points_to_use, 0), 0);
begin
  if length(v_order) < 5 or length(v_order) > 64 then
    raise exception 'Sipariş numarası geçersiz.';
  end if;
  if length(v_name) < 2 then
    raise exception 'Ad soyad en az 2 karakter olmalıdır.';
  end if;
  if length(v_phone) not between 10 and 15 then
    raise exception 'Geçerli bir telefon numarası girin.';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 50 then
    raise exception 'Sipariş ürünleri geçersiz.';
  end if;
  if p_subtotal is null or p_subtotal < 0 then
    raise exception 'Sipariş toplamı geçersiz.';
  end if;
  if p_payment_method not in ('Kapıda Nakit', 'Kapıda Kredi Kartı') then
    raise exception 'Ödeme yöntemi geçersiz.';
  end if;
  if v_points < 0 or v_points > 100000 then
    raise exception 'Kullanılacak puan miktarı geçersiz.';
  end if;
  if exists (
    select 1
      from jsonb_array_elements(p_items) as e(item)
     where jsonb_typeof(e.item) <> 'object'
        or nullif(trim(coalesce(e.item->>'name', '')), '') is null
        or coalesce(e.item->>'price', '') !~ '^[0-9]+(\.[0-9]{1,2})?$'
        or coalesce(e.item->>'qty', '') !~ '^[1-9][0-9]{0,2}$'
        or (e.item->>'qty')::integer > 99
  ) then
    raise exception 'Sipariş ürün bilgilerinde hata var.';
  end if;

  select coalesce(sum((e.item->>'price')::numeric * (e.item->>'qty')::numeric), 0)
    into v_items_subtotal
    from jsonb_array_elements(p_items) as e(item);

  if round(v_items_subtotal, 2) <> round(p_subtotal, 2) then
    raise exception 'Sepet toplamı ile ürün toplamı eşleşmiyor.';
  end if;

  if v_points > 0 then
    if length(v_old_order) < 5 then
      raise exception 'Puan kullanmak için önceki sipariş numaranızı doğrulayın.';
    end if;
    if not exists (
      select 1 from public.orders o
       where upper(trim(coalesce(o.order_number, ''))) = v_old_order
         and regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') = v_phone
    ) then
      raise exception 'Telefon ve önceki sipariş numarası eşleşmiyor.';
    end if;

    select a.points_balance
      into v_points_balance
      from public.loyalty_accounts a
     where a.phone_digits = v_phone
     for update;

    if not found or v_points_balance < v_points then
      raise exception 'Sadakat puan bakiyeniz yetersiz veya bulunamadı.';
    end if;
    if v_points > floor(p_subtotal * 10)::integer then
      raise exception 'Kullanılacak puan sipariş tutarını aşamaz.';
    end if;
    v_discount := round(v_points::numeric / 10, 2);
  end if;

  v_total := greatest(round(p_subtotal - v_discount, 2), 0);

  insert into public.orders (
    order_number, customer_name, customer_phone, customer_address,
    items, subtotal, discount_amount, points_redeemed, total,
    payment_method, status, notes
  ) values (
    v_order, v_name, v_phone, v_address,
    p_items, round(p_subtotal, 2), v_discount, v_points, v_total,
    p_payment_method, 'Yeni', v_notes
  );

  if v_points > 0 then
    update public.loyalty_accounts
       set points_balance = points_balance - v_points,
           lifetime_redeemed = lifetime_redeemed + v_points,
           updated_at = now()
     where phone_digits = v_phone
     returning points_balance into v_remaining_points;

    insert into public.loyalty_transactions (
      phone_digits, order_number, transaction_type, points_delta, description
    ) values (
      v_phone, v_order, 'redeem', -v_points,
      'Sipariş indirimi: ' || to_char(v_discount, 'FM999999990D00') || ' TL'
    );
  else
    select coalesce(a.points_balance, 0) into v_remaining_points
      from public.loyalty_accounts a
     where a.phone_digits = v_phone;
    v_remaining_points := coalesce(v_remaining_points, 0);
  end if;

  return jsonb_build_object(
    'order_number', v_order,
    'subtotal', round(p_subtotal, 2),
    'discount_amount', v_discount,
    'points_redeemed', v_points,
    'total', v_total,
    'points_balance', v_remaining_points
  );
end;
$function$;

revoke all on function public.create_customer_order_with_points(
  text,text,text,text,jsonb,numeric,text,text,integer,text
) from public;
grant execute on function public.create_customer_order_with_points(
  text,text,text,text,jsonb,numeric,text,text,integer,text
) to anon, authenticated;
