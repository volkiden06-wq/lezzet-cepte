-- Gift voucher checkout RPC wrapper. The underlying order and voucher redemption functions
-- execute in one transaction; voucher failure rolls the order insert back.
create or replace function public.create_customer_order_with_gift_voucher(
 p_order_number text,p_customer_name text,p_customer_phone text,p_customer_address text,p_items jsonb,p_subtotal numeric,p_payment_method text,p_notes text,p_points_to_use integer default 0,p_verification_order_number text default null,p_gift_voucher_code text default null,p_gift_voucher_amount numeric default 0
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_order jsonb; v_total numeric; v_voucher jsonb; v_final numeric;
begin
 if coalesce(p_gift_voucher_amount,0)<0 then raise exception 'Hediye çek tutarı geçersiz'; end if;
 if coalesce(p_gift_voucher_amount,0)>0 and length(trim(coalesce(p_gift_voucher_code,'')))<3 then raise exception 'Hediye çek kodu gerekli'; end if;
 v_order:=public.create_customer_order_with_points(p_order_number,p_customer_name,p_customer_phone,p_customer_address,p_items,p_subtotal,p_payment_method,p_notes,p_points_to_use,p_verification_order_number);
 v_total:=(v_order->>'total')::numeric;
 if coalesce(p_gift_voucher_amount,0)>v_total then raise exception 'Hediye çek tutarı sipariş kalan tutarını aşamaz'; end if;
 v_final:=v_total-coalesce(p_gift_voucher_amount,0);
 if p_gift_voucher_amount>0 then
   v_voucher:=public.redeem_gift_voucher(p_gift_voucher_code,p_gift_voucher_amount,p_order_number,p_customer_phone);
   update public.orders set total=v_final,payment_method='Hediye Çeki + '||p_payment_method,notes=coalesce(notes,'')||case when coalesce(notes,'')='' then '' else E'\\n' end||'Hediye çek: '||upper(trim(p_gift_voucher_code))||' | Kullanılan: '||p_gift_voucher_amount||' TL | Kalan: '||v_final||' TL' where order_number=p_order_number;
   return v_order||jsonb_build_object('gift_voucher_used',p_gift_voucher_amount,'gift_voucher_balance',v_voucher->'balance','final_total',v_final,'gift_voucher_code',v_voucher->'code');
 end if;
 return v_order||jsonb_build_object('gift_voucher_used',0,'final_total',v_final);
end $$;
revoke all on function public.create_customer_order_with_gift_voucher(text,text,text,text,jsonb,numeric,text,text,integer,text,text,numeric) from public;
grant execute on function public.create_customer_order_with_gift_voucher(text,text,text,text,jsonb,numeric,text,text,integer,text,text,numeric) to anon,authenticated,service_role;
