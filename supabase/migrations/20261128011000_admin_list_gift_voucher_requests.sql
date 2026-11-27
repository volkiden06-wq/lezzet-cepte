create or replace function public.admin_list_gift_voucher_requests()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if coalesce(public.is_admin(),false) is not true then raise exception 'Yönetici yetkisi gerekli'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from public.gift_voucher_requests r),'[]'::jsonb);
end $$;
revoke all on function public.admin_list_gift_voucher_requests() from public,anon;
grant execute on function public.admin_list_gift_voucher_requests() to authenticated,service_role;