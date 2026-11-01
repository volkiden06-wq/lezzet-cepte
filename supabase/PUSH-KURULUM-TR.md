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

Bu repoda `supabase/config.toml` dosyasında yalnızca `send-order-notification` için JWT kontrolü kapatılmıştır. Postgres `pg_net` isteği kullanıcı Bearer JWT'si taşımadığından bu gereklidir; fonksiyon isteği `x-order-hook-secret` başlığıyla kendi içinde doğrular.

Supabase CLI kurulu terminali proje kökünde açıp çalıştırın:

```bash
supabase login
supabase functions deploy send-order-notification --project-ref jlpqdjhxdpmighnpebkj --no-verify-jwt
```

Windows'ta hazırlanan ZIP içindeki `deploy-windows.bat` dosyası aynı işlemi yürütür.

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

## 5. Hata kontrolü

Bildirim gelmezse Supabase → Edge Functions → `send-order-notification` → Logs bölümünü kontrol edin. `pg_net` çağrılarının yanıtı `net._http_response` tablosundan incelenebilir. Siparişin veritabanına kaydedilmesi, push'ın cihaza teslim edildiğini tek başına kanıtlamaz.
