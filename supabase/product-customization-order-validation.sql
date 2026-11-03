-- YEMEK TADINDA - Server validation for product personalization at checkout
-- Run after the existing Supabase order / loyalty setup.
-- This replaces the existing create_customer_order_with_points RPC without changing its signature.
-- It validates configured extras, removal choices, preparation notes and customized item prices
-- against the current shared site_catalog product before an order can be inserted.

CREATE OR REPLACE FUNCTION public.create_customer_order_with_points(
  p_order_number text,
  p_customer_name text,
  p_customer_phone text,
  p_customer_address text,
  p_items jsonb,
  p_subtotal numeric,
  p_payment_method text,
  p_notes text,
  p_points_to_use integer DEFAULT 0,
  p_verification_order_number text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
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

  -- Server-side validation for product personalization.
  v_item jsonb;
  v_product jsonb;
  v_product_customization jsonb;
  v_selected_customization jsonb;
  v_selected_extras jsonb;
  v_selected_removed jsonb;
  v_extra jsonb;
  v_removed_name text;
  v_extra_name text;
  v_extra_price numeric(12,2);
  v_allowed_extra_price numeric(12,2);
  v_extra_total numeric(12,2);
  v_declared_extra_total numeric(12,2);
  v_base_price numeric(12,2);
  v_preparation_note text;
BEGIN
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

  -- Do not trust the browser for add-on names or prices.
  for v_item in
    select value from pg_catalog.jsonb_array_elements(p_items)
  loop
    if coalesce(v_item->>'customization_extra_total', '0') !~ '^[0-9]+(\.[0-9]{1,2})?$' then
      raise exception 'Kişiselleştirme ekstra toplamı geçersiz.';
    end if;
    v_declared_extra_total := coalesce((v_item->>'customization_extra_total')::numeric, 0);
    v_selected_customization := v_item->'customization';

    if v_selected_customization is null or v_selected_customization = 'null'::jsonb then
      if v_declared_extra_total <> 0 then
        raise exception 'Kişiselleştirme fiyatı doğrulanamadı.';
      end if;
      continue;
    end if;

    if pg_catalog.jsonb_typeof(v_selected_customization) <> 'object' then
      raise exception 'Ürün kişiselleştirme bilgisi geçersiz.';
    end if;

    select p.value
      into v_product
      from public.site_catalog c
      cross join lateral pg_catalog.jsonb_array_elements(c.products) as p(value)
     where c.id = 1
       and p.value->>'id' = v_item->>'id'
       and coalesce(p.value->>'active', 'true') = 'true'
     limit 1;

    if v_product is null then
      raise exception 'Kişiselleştirilen ürün güncel menüde bulunamadı.';
    end if;

    v_product_customization := v_product->'customization';
    if coalesce(v_product_customization->>'enabled', 'false') <> 'true' then
      raise exception 'Bu ürün için kişiselleştirme şu anda etkin değil.';
    end if;

    if coalesce(v_product->>'price', '') !~ '^[0-9]+(\.[0-9]{1,2})?$'
       or coalesce(v_item->>'base_price', '') !~ '^[0-9]+(\.[0-9]{1,2})?$' then
      raise exception 'Ürünün temel fiyatı doğrulanamadı.';
    end if;

    v_base_price := (v_product->>'price')::numeric;
    if (v_item->>'base_price')::numeric <> v_base_price then
      raise exception 'Ürünün fiyatı değişmiş. Lütfen sepetinizi yenileyin.';
    end if;

    v_selected_removed := coalesce(v_selected_customization->'removed_ingredients', '[]'::jsonb);
    if pg_catalog.jsonb_typeof(v_selected_removed) <> 'array'
       or pg_catalog.jsonb_array_length(v_selected_removed) > 20 then
      raise exception 'Çıkarılacak malzeme listesi geçersiz.';
    end if;

    for v_removed_name in
      select value from pg_catalog.jsonb_array_elements_text(v_selected_removed)
    loop
      if length(trim(v_removed_name)) = 0
         or not exists (
           select 1
             from pg_catalog.jsonb_array_elements_text(
               coalesce(v_product_customization->'removableIngredients', '[]'::jsonb)
             ) as allowed(value)
            where allowed.value = trim(v_removed_name)
         ) then
        raise exception 'Seçilen çıkarılacak malzeme bu üründe tanımlı değil.';
      end if;
    end loop;

    v_selected_extras := coalesce(v_selected_customization->'extras', '[]'::jsonb);
    if pg_catalog.jsonb_typeof(v_selected_extras) <> 'array'
       or pg_catalog.jsonb_array_length(v_selected_extras) > 20 then
      raise exception 'Ekstra malzeme listesi geçersiz.';
    end if;

    v_extra_total := 0;
    for v_extra in
      select value from pg_catalog.jsonb_array_elements(v_selected_extras)
    loop
      v_extra_name := trim(coalesce(v_extra->>'name', ''));
      if v_extra_name = ''
         or coalesce(v_extra->>'price', '') !~ '^[0-9]+(\.[0-9]{1,2})?$' then
        raise exception 'Ekstra malzeme bilgisi geçersiz.';
      end if;
      v_extra_price := (v_extra->>'price')::numeric;

      select (allowed.value->>'price')::numeric
        into v_allowed_extra_price
        from pg_catalog.jsonb_array_elements(
          coalesce(v_product_customization->'extras', '[]'::jsonb)
        ) as allowed(value)
       where lower(trim(allowed.value->>'name')) = lower(v_extra_name)
         and coalesce(allowed.value->>'price', '') ~ '^[0-9]+(\.[0-9]{1,2})?$'
       limit 1;

      if not found or v_allowed_extra_price <> v_extra_price then
        raise exception 'Ekstra malzeme veya fiyatı ürün ayarlarıyla eşleşmiyor.';
      end if;

      v_extra_total := v_extra_total + v_extra_price;
    end loop;

    if round(v_extra_total, 2) <> round(v_declared_extra_total, 2) then
      raise exception 'Ekstra malzeme toplamı doğrulanamadı.';
    end if;

    v_preparation_note := trim(coalesce(v_selected_customization->>'preparation_note', ''));
    if length(v_preparation_note) > 300 then
      raise exception 'Hazırlama notu 300 karakteri aşamaz.';
    end if;
    if v_preparation_note <> ''
       and coalesce(v_product_customization->>'allowNote', 'true') <> 'true' then
      raise exception 'Bu ürün için özel hazırlama notu kapalı.';
    end if;

    if coalesce(v_item->>'price', '') !~ '^[0-9]+(\.[0-9]{1,2})?$'
       or (v_item->>'price')::numeric <> round(v_base_price + v_extra_total, 2) then
      raise exception 'Kişiselleştirilmiş ürün fiyatı doğrulanamadı.';
    end if;
  end loop;

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

    if not (
      exists (
        select 1 from public.orders o
         where upper(trim(coalesce(o.order_number, ''))) = v_old_order
           and regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') = v_phone
      )
      or exists (
        select 1 from public.order_history_archive o
         where upper(trim(coalesce(o.order_number, ''))) = v_old_order
           and regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g') = v_phone
      )
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

revoke all on function public.create_customer_order_with_points(text,text,text,text,jsonb,numeric,text,text,integer,text) from public;
grant execute on function public.create_customer_order_with_points(text,text,text,text,jsonb,numeric,text,text,integer,text) to anon, authenticated;
