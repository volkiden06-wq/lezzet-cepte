-- Push alerts for newly submitted gift voucher payment claims.
DO $$ BEGIN
 IF to_regclass('public.gift_voucher_requests') IS NULL THEN RAISE EXCEPTION 'gift_voucher_requests table missing'; END IF;
 IF to_regclass('public.admin_push_subscriptions') IS NULL THEN RAISE EXCEPTION 'admin_push_subscriptions missing'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='net') THEN RAISE EXCEPTION 'pg_net missing'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='vault') THEN RAISE EXCEPTION 'Vault missing'; END IF;
 IF NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name='order_push_hook_secret' AND decrypted_secret<>'' ) THEN RAISE EXCEPTION 'Push hook secret missing in Vault'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.notify_new_gift_voucher_push()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE hook_secret text;
BEGIN
 IF NEW.status <> 'pending' THEN RETURN NEW; END IF;
 SELECT decrypted_secret INTO hook_secret FROM vault.decrypted_secrets WHERE name='order_push_hook_secret' ORDER BY created_at DESC LIMIT 1;
 IF hook_secret IS NULL OR hook_secret='' THEN RAISE WARNING 'push secret missing'; RETURN NEW; END IF;
 PERFORM net.http_post(url := 'https://jlpqdjhxdpmighnpebkj.supabase.co/functions/v1/rapid-service',headers := pg_catalog.jsonb_build_object('Content-Type','application/json','x-order-hook-secret',hook_secret),body := pg_catalog.jsonb_build_object('type','gift_voucher','record',pg_catalog.jsonb_build_object('id',NEW.id,'request_code',NEW.request_code,'amount',NEW.amount,'buyer_name',NEW.buyer_name)),timeout_milliseconds := 10000);
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_notify_new_gift_voucher_push ON public.gift_voucher_requests;
CREATE TRIGGER trg_notify_new_gift_voucher_push AFTER INSERT ON public.gift_voucher_requests FOR EACH ROW EXECUTE FUNCTION public.notify_new_gift_voucher_push();
