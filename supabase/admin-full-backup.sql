-- YEMEK TADINDA - Yöneticiye özel tam yedek dışa aktarma
-- Bu dosyayı çalıştırmadan önce supabase/product-reviews.sql dosyasını da kurun.
-- Parola, service-role key, VAPID private key ve cihaz bildirim tokenları dışa aktarılmaz.

create or replace function public.admin_export_full_backup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_catalog jsonb;
  v_orders jsonb;
  v_archive jsonb;
  v_loyalty_accounts jsonb;
  v_loyalty_transactions jsonb;
  v_visitors jsonb;
  v_reviews jsonb;
  v_storage_objects jsonb;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Tam yedek almak için yönetici oturumu gerekli.'
      using errcode = '42501';
  end if;

  select pg_catalog.to_jsonb(c) into v_catalog
  from public.site_catalog c where c.id = 1;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(o) order by o.created_at, o.id), '[]'::jsonb)
  into v_orders from public.orders o;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) order by a.archived_at, a.archive_id), '[]'::jsonb)
  into v_archive from public.order_history_archive a;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a) order by a.phone_digits), '[]'::jsonb)
  into v_loyalty_accounts from public.loyalty_accounts a;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(t) order by t.created_at, t.id), '[]'::jsonb)
  into v_loyalty_transactions from public.loyalty_transactions t;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(v) order by v.visit_date, v.visitor_id), '[]'::jsonb)
  into v_visitors from public.site_daily_visitors v;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(r) order by r.created_at, r.id), '[]'::jsonb)
  into v_reviews from public.product_reviews r;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'bucket_id', o.bucket_id,
        'name', o.name,
        'updated_at', o.updated_at,
        'created_at', o.created_at,
        'metadata', o.metadata
      ) order by o.bucket_id, o.name
    ), '[]'::jsonb
  )
  into v_storage_objects
  from storage.objects o
  where o.bucket_id = 'push-notification-images';

  return pg_catalog.jsonb_build_object(
    'backup_format', 'YEMEK-TADINDA-FULL-BACKUP-V1',
    'exported_at', pg_catalog.clock_timestamp(),
    'project_ref', 'jlpqdjhxdpmighnpebkj',
    'database', pg_catalog.jsonb_build_object(
      'site_catalog', coalesce(v_catalog, '{}'::jsonb),
      'orders', v_orders,
      'order_history_archive', v_archive,
      'loyalty_accounts', v_loyalty_accounts,
      'loyalty_transactions', v_loyalty_transactions,
      'site_daily_visitors', v_visitors,
      'product_reviews', v_reviews,
      'catalog_sync_events', (
        select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(e)), '[]'::jsonb)
        from public.catalog_sync_events e
      ),
      'storage_objects', v_storage_objects,
      'device_notification_subscription_counts', pg_catalog.jsonb_build_object(
        'customer_devices', (select count(*) from public.push_subscriptions),
        'admin_devices', (select count(*) from public.admin_push_subscriptions),
        'note', 'Push abonelik uçları cihazlara özeldir; yeni bilgisayar/telefonda bildirim izni yeniden verilmelidir.'
      ),
      'admin_access', pg_catalog.jsonb_build_object(
        'admin_user_count', (select count(*) from public.admin_users),
        'note', 'Supabase Auth parolaları dışa aktarılmaz; mevcut yönetici hesabı kullanılır.'
      )
    ),
    'counts', pg_catalog.jsonb_build_object(
      'products', coalesce(pg_catalog.jsonb_array_length(v_catalog->'products'), 0),
      'categories', coalesce(pg_catalog.jsonb_array_length(v_catalog->'categories'), 0),
      'campaigns', coalesce(pg_catalog.jsonb_array_length(v_catalog->'campaigns'), 0),
      'orders', pg_catalog.jsonb_array_length(v_orders),
      'archived_orders', pg_catalog.jsonb_array_length(v_archive),
      'loyalty_accounts', pg_catalog.jsonb_array_length(v_loyalty_accounts),
      'loyalty_transactions', pg_catalog.jsonb_array_length(v_loyalty_transactions),
      'site_visits', pg_catalog.jsonb_array_length(v_visitors),
      'product_reviews', pg_catalog.jsonb_array_length(v_reviews),
      'published_product_reviews', (select count(*) from public.product_reviews where moderation_status = 'approved'),
      'storage_objects', pg_catalog.jsonb_array_length(v_storage_objects)
    )
  );
end;
$function$;

revoke all on function public.admin_export_full_backup() from public, anon;
grant execute on function public.admin_export_full_backup() to authenticated;
