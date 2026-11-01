# LEZZET CEPTE – Otomatik yeni sipariş bildirimi

Yeni sipariş `public.orders` tablosuna eklendiğinde yalnızca yönetici olarak yetkilendirilmiş cihazlara Web Push gönderilir. Müşterilerin kampanya abonelikleri ayrı tabloda kalır; müşteri cihazlarına başka siparişlerin adı veya tutarı gönderilmez.

## 1. Function Secrets

Supabase Dashboard → Edge Functions → Secrets bölümünde şu değerleri doğrulayın:

- `ORDER_PUSH_HOOK_SECRET`
- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`
- `VAPID_SUBJECT`

Fonksiyon Supabase tarafından sağlanan `SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` ortam değişkenlerini de kullanır. Gizli anahtarları GitHub'a, site koduna veya sohbet mesajlarına koymayın.

## 2. Edge Function dağıtımı

Supabase panelinde mevcut fonksiyonun gerçek adresi `.../functions/v1/rapid-service` olduğundan GitHub kaynağı `supabase/functions/rapid-service/index.ts` olarak tutulur. `supabase/config.toml` içinde bu fonksiyon için JWT doğrulaması kapalıdır; Postgres `pg_net` isteği kullanıcı Bearer JWT'si taşımadığı için fonksiyon isteği `x-order-hook-secret` başlığıyla kendi içinde doğrular.

Windows'ta GitHub deposunun ZIP'ini indirip açın. Supabase CLI kurulu terminalde proje kökünde `supabase/deploy-push-windows.bat` dosyasını çalıştırın. Bu işlem mevcut `rapid-service` slug'ına güncel kaynak kodunu dağıtır.

## 3. SQL kurulumu

1. Database → Extensions bölümünden `pg_net` ve `Vault` etkin olmalı.
2. Daha önce `push-notifications.sql` çalıştırılmış ve `public.push_subscriptions` tablosu oluşturulmuş olmalı. Bu tablo yalnızca ziyaretçi kampanya/duyuru abonelikleri içindir.
3. `supabase/order-push-trigger.sql` dosyasını açın. `REPLACE_WITH_SECRET_IN_SUPABASE_ONLY` metnini Function Secrets içindeki `ORDER_PUSH_HOOK_SECRET` değeriyle birebir değiştirin. Değerin kendisini bana veya GitHub'a göndermeyin.
4. Dosyanın tamamını Supabase SQL Editor'de çalıştırın.

SQL; `public.admin_push_subscriptions` adlı ayrı, istemciye kapalı tabloyu ve yalnızca `is_admin()` doğrulamasından geçen giriş yapmış yöneticinin çağırabildiği `save_admin_push_subscription` RPC fonksiyonunu oluşturur. Ayrıca sipariş tablosu kolonlarını ve gerekli uzantıları kontrol eder. Son sorguda `trg_notify_new_order_push` görünmelidir.

## 4. Yönetici cihazında bildirim izni

1. `https://yemektadinda.com` adresini bildirim almak istediğiniz bilgisayarda/telefonda açın.
2. Yönetici girişi yapın.
3. Yönetim Paneli → Bildirim Gönder bölümüne girin.
4. **BU CİHAZDA SİPARİŞ BİLDİRİMLERİNİ AÇ** düğmesine basın ve tarayıcı iznini verin.
5. Yeni test siparişi oluşturun. Yalnızca bu şekilde yönetici olarak kaydedilmiş cihazlarda **YENİ SİPARİŞ ALINDI** bildirimi görünmelidir.

Kampanya/duyuru bildirimi gönderme alanı ise müşterilerin normal kampanya aboneliklerini kullanmaya devam eder.

## 5. Kurulumu doğrulama\n\nSupabase SQL Editor'de `supabase/verify-push-setup.sql` dosyasını çalıştırın. Bu sorgu salt-okunurdur; ürün, kategori veya sipariş kayıtlarını değiştirmez. `orders_table_exists`, `customer_push_table_exists`, `admin_push_table_exists`, `admin_subscription_rpc_exists`, `pg_net_enabled`, `vault_available`, `order_number_column_exists`, `customer_name_column_exists`, `total_column_exists` ve `order_push_trigger_enabled` sonuçlarının tamamı `true` olmalıdır.\n\n## 6. Hata kontrolü

Bildirim gelmezse Supabase → Edge Functions → `rapid-service` → Logs bölümünü kontrol edin. `pg_net` çağrılarının yanıtı `net._http_response` tablosundan incelenebilir. Siparişin veritabanına kaydedilmesi, push'ın cihaza teslim edildiğini tek başına kanıtlamaz.
