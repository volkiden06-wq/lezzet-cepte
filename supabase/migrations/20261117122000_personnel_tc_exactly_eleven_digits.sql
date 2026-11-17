-- TC Kimlik No is a private employee field. Validate only the format:
-- exactly 11 numeric characters. No check-digit or government/SSK lookup.
create or replace function public.admin_save_personnel(
 p_personnel_id bigint,p_full_name text,p_start_date date,p_job_title text,p_national_id text,p_phone text,p_is_active boolean
)
returns bigint language plpgsql security definer set search_path=''
as $$
declare
 v_key text;
 v_id bigint;
 v_tc text:=coalesce(p_national_id,'');
 v_cipher text;
 v_hash text;
begin
 if not coalesce(public.is_admin(),false) then raise exception 'Yönetici yetkisi gerekli.' using errcode='42501'; end if;
 if p_full_name is null or char_length(btrim(p_full_name)) not between 2 and 150 then raise exception 'Ad soyad 2-150 karakter arasında olmalı.'; end if;
 if p_start_date is null then raise exception 'İşe başlama tarihi zorunludur.'; end if;
 if p_job_title is null or char_length(btrim(p_job_title)) not between 2 and 120 then raise exception 'Görev 2-120 karakter arasında olmalı.'; end if;
 if char_length(coalesce(p_phone,''))>30 then raise exception 'Telefon alanı çok uzun.'; end if;
 select decrypted_secret into v_key from vault.decrypted_secrets where name='yemektadinda_personnel_tc_key' limit 1;
 if v_key is null then raise exception 'Kimlik şifreleme anahtarı bulunamadı.'; end if;
 if v_tc<>'' then
  if v_tc !~ '^[0-9]{11}$' then raise exception 'TC alanına yalnızca 11 rakam yazılmalıdır.'; end if;
  v_cipher:=encode(extensions.pgp_sym_encrypt(v_tc,v_key,'cipher-algo=aes256'),'hex');
  v_hash:=encode(extensions.hmac(v_tc,v_key,'sha256'),'hex');
 elsif p_personnel_id is null then
  raise exception 'Yeni personel için 11 rakamdan oluşan TC alanı zorunludur.';
 end if;
 if p_personnel_id is null then
  insert into public.personnel(full_name,start_date,job_title,national_id_cipher,national_id_hash,phone,is_active,created_by)
  values(btrim(p_full_name),p_start_date,btrim(p_job_title),v_cipher,v_hash,btrim(coalesce(p_phone,'')),coalesce(p_is_active,true),auth.uid())
  returning id into v_id;
 else
  update public.personnel set full_name=btrim(p_full_name),start_date=p_start_date,job_title=btrim(p_job_title),
   national_id_cipher=coalesce(v_cipher,national_id_cipher),national_id_hash=coalesce(v_hash,national_id_hash),
   phone=btrim(coalesce(p_phone,'')),is_active=coalesce(p_is_active,true),updated_at=now()
  where id=p_personnel_id returning id into v_id;
  if v_id is null then raise exception 'Personel kaydı bulunamadı.'; end if;
 end if;
 return v_id;
exception when unique_violation then raise exception 'Bu TC Kimlik No ile kayıtlı başka personel var.';
end $$;

revoke all on function public.admin_save_personnel(bigint,text,date,text,text,text,boolean) from public,anon;
grant execute on function public.admin_save_personnel(bigint,text,date,text,text,text,boolean) to authenticated;
