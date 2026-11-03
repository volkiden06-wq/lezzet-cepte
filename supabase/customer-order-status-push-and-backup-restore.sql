-- YEMEK TADINDA: müşteri sipariş durumu bildirimleri + tam yedek geri yükleme.
-- Bu SQL, 2026-11-03 tarihinde jlpqdjhxdpmighnpebkj projesine uygulanmıştır.
-- Veri taşıma/silme işlemi bu dosyayı çalıştırınca değil, yönetim panelinden
-- yönetici onayıyla admin_restore_full_backup RPC çağrılınca yapılır.

CREATE TABLE IF NOT EXISTS public.customer_order_push_links (
  order_number text NOT NULL,
  phone_digits text NOT NULL,
  endpoint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customer_order_push_links_pkey PRIMARY KEY (order_number, endpoint),
  CONSTRAINT customer_order_push_links_endpoint_fkey
    FOREIGN KEY (endpoint) REFERENCES public.push_subscriptions(endpoint) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS customer_order_push_links_order_number_idx
  ON public.customer_order_push_links(order_number);
ALTER TABLE public.customer_order_push_links ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.customer_order_push_links FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON TABLE public.customer_order_push_links TO service_role;

CREATE OR REPLACE FUNCTION public.register_customer_order_push(
  p_order_number text, p_phone text, p_endpoint text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_order text := upper(trim(coalesce(p_order_number,'')));
  v_phone text := pg_catalog.regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
BEGIN
  IF length(v_order) NOT BETWEEN 5 AND 80
     OR length(v_phone) NOT BETWEEN 10 AND 15
     OR p_endpoint IS NULL OR length(p_endpoint)<30 THEN
    RAISE EXCEPTION 'Sipariş numarası, telefon veya bildirim cihazı geçersiz.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.push_subscriptions s ON s.endpoint=p_endpoint
    WHERE upper(trim(coalesce(o.order_number,'')))=v_order
      AND pg_catalog.regexp_replace(coalesce(o.customer_phone,''),'[^0-9]','','g')=v_phone
      AND coalesce(o.status,'Yeni') NOT IN ('Teslim edildi','İptal','Kapalı')
  ) THEN
    RAISE EXCEPTION 'Bu cihaz, sipariş numarası ve telefonla eşleşen aktif sipariş bulunamadı.';
  END IF;
  INSERT INTO public.customer_order_push_links(order_number,phone_digits,endpoint,updated_at)
  VALUES(v_order,v_phone,p_endpoint,now())
  ON CONFLICT(order_number,endpoint) DO UPDATE
    SET phone_digits=EXCLUDED.phone_digits,updated_at=now();
  RETURN pg_catalog.jsonb_build_object('success',true,'order_number',v_order);
END;
$function$;
REVOKE ALL ON FUNCTION public.register_customer_order_push(text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_customer_order_push(text,text,text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_customer_order_status_push()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE hook_secret text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.order_number IS NULL THEN RETURN NEW; END IF;
  SELECT ds.decrypted_secret INTO hook_secret
  FROM vault.decrypted_secrets ds
  WHERE ds.name='order_push_hook_secret'
  ORDER BY ds.created_at DESC LIMIT 1;
  IF hook_secret IS NULL OR hook_secret='' THEN
    RAISE WARNING 'order_push_hook_secret missing; customer status push skipped';
    RETURN NEW;
  END IF;
  PERFORM net.http_post(
    url := 'https://jlpqdjhxdpmighnpebkj.supabase.co/functions/v1/rapid-service',
    headers := pg_catalog.jsonb_build_object(
      'Content-Type','application/json','x-order-hook-secret',hook_secret
    ),
    body := pg_catalog.jsonb_build_object(
      'type','order_status',
      'record',pg_catalog.jsonb_build_object('order_number',NEW.order_number,'status',NEW.status)
    ),
    timeout_milliseconds := 10000
  );
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.notify_customer_order_status_push() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_notify_customer_order_status_push ON public.orders;
CREATE TRIGGER trg_notify_customer_order_status_push
AFTER UPDATE OF status ON public.orders
FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION public.notify_customer_order_status_push();

CREATE OR REPLACE FUNCTION public.admin_restore_full_backup(p_backup jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_db jsonb;
  v_catalog public.site_catalog%ROWTYPE;
  v_restored jsonb;
  v_seq text;
BEGIN
  IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN
    RAISE EXCEPTION 'Yedeği geri yüklemek için yönetici oturumu gerekli.' USING errcode='42501';
  END IF;
  IF p_backup IS NULL
    OR p_backup->>'backup_format' IS DISTINCT FROM 'YEMEK-TADINDA-FULL-BACKUP-V1'
    OR p_backup->>'project_ref' IS DISTINCT FROM 'jlpqdjhxdpmighnpebkj' THEN
    RAISE EXCEPTION 'Yedek biçimi veya proje kimliği geçersiz. Hiçbir veri değiştirilmedi.';
  END IF;
  v_db:=p_backup->'database';
  IF jsonb_typeof(v_db) IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_db->'site_catalog') IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_db->'orders') IS DISTINCT FROM 'array'
    OR jsonb_typeof(v_db->'order_history_archive') IS DISTINCT FROM 'array'
    OR jsonb_typeof(v_db->'loyalty_accounts') IS DISTINCT FROM 'array'
    OR jsonb_typeof(v_db->'loyalty_transactions') IS DISTINCT FROM 'array'
    OR jsonb_typeof(v_db->'site_daily_visitors') IS DISTINCT FROM 'array'
    OR jsonb_typeof(v_db->'product_reviews') IS DISTINCT FROM 'array'
    OR jsonb_typeof(v_db->'catalog_sync_events') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Yedek eksik veya bozuk; hiçbir veri değiştirilmedi.';
  END IF;
  IF coalesce((v_db->'site_catalog'->>'id')::integer,0)<>1
    OR jsonb_typeof(v_db->'site_catalog'->'products') IS DISTINCT FROM 'array'
    OR jsonb_typeof(v_db->'site_catalog'->'categories') IS DISTINCT FROM 'array'
    OR jsonb_typeof(v_db->'site_catalog'->'campaigns') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Menü, kategori veya kampanya yedeği geçersiz; hiçbir veri değiştirilmedi.';
  END IF;
  IF jsonb_typeof(p_backup->'counts') IS DISTINCT FROM 'object'
    OR (p_backup->'counts'->>'orders')::integer<>jsonb_array_length(v_db->'orders')
    OR (p_backup->'counts'->>'archived_orders')::integer<>jsonb_array_length(v_db->'order_history_archive')
    OR (p_backup->'counts'->>'loyalty_accounts')::integer<>jsonb_array_length(v_db->'loyalty_accounts')
    OR (p_backup->'counts'->>'loyalty_transactions')::integer<>jsonb_array_length(v_db->'loyalty_transactions')
    OR (p_backup->'counts'->>'site_visits')::integer<>jsonb_array_length(v_db->'site_daily_visitors')
    OR (p_backup->'counts'->>'product_reviews')::integer<>jsonb_array_length(v_db->'product_reviews') THEN
    RAISE EXCEPTION 'Yedek kayıt sayıları tutarsız; hiçbir veri değiştirilmedi.';
  END IF;

  -- İçeri alma sırasında eski sipariş bildirimleri ve puan tetikleyicileri çalıştırılmaz.
  ALTER TABLE public.orders DISABLE TRIGGER USER;
  DELETE FROM public.loyalty_transactions;
  DELETE FROM public.loyalty_accounts;
  DELETE FROM public.order_history_archive;
  DELETE FROM public.orders;
  DELETE FROM public.site_daily_visitors;
  DELETE FROM public.product_reviews;
  DELETE FROM public.catalog_sync_events;

  INSERT INTO public.orders SELECT x.* FROM pg_catalog.jsonb_populate_recordset(NULL::public.orders,v_db->'orders') x;
  INSERT INTO public.order_history_archive SELECT x.* FROM pg_catalog.jsonb_populate_recordset(NULL::public.order_history_archive,v_db->'order_history_archive') x;
  INSERT INTO public.loyalty_accounts SELECT x.* FROM pg_catalog.jsonb_populate_recordset(NULL::public.loyalty_accounts,v_db->'loyalty_accounts') x;
  INSERT INTO public.loyalty_transactions SELECT x.* FROM pg_catalog.jsonb_populate_recordset(NULL::public.loyalty_transactions,v_db->'loyalty_transactions') x;
  INSERT INTO public.site_daily_visitors SELECT x.* FROM pg_catalog.jsonb_populate_recordset(NULL::public.site_daily_visitors,v_db->'site_daily_visitors') x;
  INSERT INTO public.product_reviews SELECT x.* FROM pg_catalog.jsonb_populate_recordset(NULL::public.product_reviews,v_db->'product_reviews') x;
  INSERT INTO public.catalog_sync_events SELECT x.* FROM pg_catalog.jsonb_populate_recordset(NULL::public.catalog_sync_events,v_db->'catalog_sync_events') x;

  v_catalog:=pg_catalog.jsonb_populate_record(NULL::public.site_catalog,v_db->'site_catalog');
  INSERT INTO public.site_catalog(id,products,categories,updated_at,campaigns)
  VALUES(v_catalog.id,v_catalog.products,v_catalog.categories,now(),v_catalog.campaigns)
  ON CONFLICT(id) DO UPDATE
    SET products=EXCLUDED.products,categories=EXCLUDED.categories,campaigns=EXCLUDED.campaigns,updated_at=clock_timestamp();

  DELETE FROM public.customer_order_push_links l
  WHERE NOT EXISTS (
    SELECT 1 FROM public.orders o
    WHERE upper(trim(coalesce(o.order_number,'')))=l.order_number
      AND pg_catalog.regexp_replace(coalesce(o.customer_phone,''),'[^0-9]','','g')=l.phone_digits
      AND coalesce(o.status,'Yeni') NOT IN ('Teslim edildi','İptal','Kapalı')
  );
  ALTER TABLE public.orders ENABLE TRIGGER USER;

  v_seq:=pg_catalog.pg_get_serial_sequence('public.orders','id');
  IF v_seq IS NOT NULL THEN PERFORM pg_catalog.setval(v_seq::regclass,coalesce((SELECT max(id) FROM public.orders),1),EXISTS(SELECT 1 FROM public.orders)); END IF;
  v_seq:=pg_catalog.pg_get_serial_sequence('public.order_history_archive','archive_id');
  IF v_seq IS NOT NULL THEN PERFORM pg_catalog.setval(v_seq::regclass,coalesce((SELECT max(archive_id) FROM public.order_history_archive),1),EXISTS(SELECT 1 FROM public.order_history_archive)); END IF;
  v_seq:=pg_catalog.pg_get_serial_sequence('public.loyalty_transactions','id');
  IF v_seq IS NOT NULL THEN PERFORM pg_catalog.setval(v_seq::regclass,coalesce((SELECT max(id) FROM public.loyalty_transactions),1),EXISTS(SELECT 1 FROM public.loyalty_transactions)); END IF;
  v_seq:=pg_catalog.pg_get_serial_sequence('public.product_reviews','id');
  IF v_seq IS NOT NULL THEN PERFORM pg_catalog.setval(v_seq::regclass,coalesce((SELECT max(id) FROM public.product_reviews),1),EXISTS(SELECT 1 FROM public.product_reviews)); END IF;

  SELECT pg_catalog.jsonb_build_object(
    'products',jsonb_array_length(v_catalog.products),
    'categories',jsonb_array_length(v_catalog.categories),
    'campaigns',jsonb_array_length(v_catalog.campaigns),
    'orders',(SELECT count(*) FROM public.orders),
    'archived_orders',(SELECT count(*) FROM public.order_history_archive),
    'loyalty_accounts',(SELECT count(*) FROM public.loyalty_accounts),
    'loyalty_transactions',(SELECT count(*) FROM public.loyalty_transactions),
    'site_visits',(SELECT count(*) FROM public.site_daily_visitors),
    'product_reviews',(SELECT count(*) FROM public.product_reviews)
  ) INTO v_restored;
  RETURN pg_catalog.jsonb_build_object(
    'success',true,'restored_at',clock_timestamp(),'counts',v_restored,
    'note','Bildirim cihazları, yönetici hesapları ve parolalar güvenlik nedeniyle geri yüklenmez.'
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_restore_full_backup(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_restore_full_backup(jsonb) TO authenticated;
