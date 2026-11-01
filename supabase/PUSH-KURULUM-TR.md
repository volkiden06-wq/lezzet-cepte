# LEZZET CEPTE – Yeni sipariş bildirimi kurulumu

Yeni sipariş `public.orders` tablosuna eklendiğinde Supabase, kayıtlı cihazlara Web Push bildirimi yollar.

1. Bu repodaki `supabase/config.toml` ve `supabase/functions/send-order-notification/index.ts` dosyalarını Supabase CLI ile birlikte kullanın.
2. Supabase CLI terminalinden:
   ```bash
   supabase login
   supabase functions deploy send-order-notification --project-ref jlpqdjhxdpmighnpebkj --no-verify-jwt
   ```
3. Function Secrets'te `ORDER_PUSH_HOOK_SECRET`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` değerlerinin bulunduğunu doğrulayın. Fonksiyon Supabase'in `SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` ortam değişkenlerini de kullanır.
4. Database > Extensions bölümünden `pg_net` ve `Vault` etkin olsun. Önceden `push-notifications.sql` çalıştırılmış ve `public.push_subscriptions` tablosu oluşturulmuş olmalı.
5. `supabase/order-push-trigger.sql` içindeki `REPLACE_WITH_SECRET_IN_SUPABASE_ONLY` metnini Function Secrets'teki `ORDER_PUSH_HOOK_SECRET` ile birebir değiştirip Supabase SQL Editor'de çalıştırın.
6. SQL sonuçlarında `trg_notify_new_order_push` görünmeli. Bildirim alacak cihazda siteden bildirim izni verin ve test siparişi oluşturun.

Gizli anahtarları GitHub'a veya site koduna koymayın. Bu kurulum SQL'i secret değerini repo içine eklemeden kullanmanız içindir.
