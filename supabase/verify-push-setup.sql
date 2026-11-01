-- LEZZET CEPTE / YEMEK TADINDA
-- Salt-okunur kontrol. Mevcut urun, kategori veya siparis verilerini degistirmez.

SELECT
  to_regclass('public.orders') IS NOT NULL AS orders_table_exists,
  to_regclass('public.push_subscriptions') IS NOT NULL AS customer_push_table_exists,
  to_regclass('public.admin_push_subscriptions') IS NOT NULL AS admin_push_table_exists,
  to_regprocedure('public.save_admin_push_subscription(text,jsonb,text)') IS NOT NULL AS admin_subscription_rpc_exists,
  EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_net'
  ) AS pg_net_enabled,
  to_regclass('vault.decrypted_secrets') IS NOT NULL AS vault_available,
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'order_number'
  ) AS order_number_column_exists,
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'customer_name'
  ) AS customer_name_column_exists,
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'total'
  ) AS total_column_exists,
  EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_notify_new_order_push'
      AND tgrelid = to_regclass('public.orders')
      AND NOT tgisinternal
      AND tgenabled <> 'D'
  ) AS order_push_trigger_enabled;
