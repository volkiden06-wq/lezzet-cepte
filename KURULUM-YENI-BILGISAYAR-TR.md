# YEMEK TADINDA — Yeni Bilgisayara Kurulum ve Tam Yedek

Bu paket, **YEMEK TADINDA** web sitesinin kaynak dosyalarını ve yönetim altyapısını içerir.

## Önemli: Yönetim verileri nerede tutulur?

Ürünler, kategoriler, kampanyalar, siparişler, müşteri sadakat kayıtları ve raporların asıl kaynağı mevcut Supabase projesidir. Başka bir bilgisayardan aynı siteyi yönetmek için veritabanını yeniden kurmanız gerekmez:

1. Yeni bilgisayarda Chrome/Edge açın.
2. `https://yemektadinda.com` adresine girin.
3. Mevcut yönetici hesabınızla giriş yapın.
4. Bilgisayardaki tüm değişiklikler aynı Supabase projesine kaydedilir ve diğer cihazlara eşitlenir.
5. Yeni bilgisayarda sipariş bildirimi almak istiyorsanız Yönetim Paneli → Bildirim Gönder bölümünden o cihazın bildirim iznini ayrıca açın.

## Kaynak kodu yerel olarak çalıştırma

- Windows'ta bu ZIP'i bir klasöre çıkarın.
- Python 3 kuruluysa `BASLAT-YEREL-WINDOWS.bat` dosyasına çift tıklayın.
- Tarayıcıda `http://localhost:8080` açılır.
- Bu yerel önizleme aynı Supabase projesine bağlanır; gerçek verileri değiştirebilen yönetici işlemleri için yönetici hesabınızla giriş yapmanız gerekir.

## Site kodunu değiştirme ve yayınlama

Bu klasör GitHub deposunun kaynak kopyasıdır. Canlı site GitHub/Netlify dağıtımı üzerinden yayınlanır. Kod değişikliklerini canlıya almak için aynı GitHub deposuna yetkili hesabınızla göndermeniz veya Netlify'da bu depoya bağlı siteyi yeniden dağıtmanız gerekir.

- Ana sayfa ve yönetim paneli: `index.html`
- Çevrimdışı önbellek ve PWA: `sw.js`, `manifest.webmanifest`
- Netlify ayarları ve bildirim fonksiyonu: `netlify/`, `netlify.toml`
- Supabase Edge Functions: `supabase/functions/`
- SQL kurulum ve doğrulama dosyaları: `database.sql`, `push-notifications.sql`, `supabase/*.sql`
- Android TWA kaynakları: `android-app/`

## Canlı verilerin tam JSON yedeğini alma

Bu ZIP kaynak kodu paketidir. Canlı verilerin ayrıca JSON yedeğini alın:

1. **Mevcut yönetici bilgisayarından** `https://yemektadinda.com` açın.
2. Yönetici girişi yapın.
3. Yönetim Paneli → **Raporlar** bölümüne girin.
4. **TAM SİTE YEDEĞİ (VERİ + GÖRSELLER)** düğmesine basın.
5. İndirilen `YEMEK-TADINDA-TAM-YEDEK-....json` dosyasını kaynak ZIP ile aynı yedek klasöründe saklayın.

Bu JSON; ortak ürün/kategori/kampanya kataloğunu, aktif ve arşiv siparişlerini, sadakat hesap ve hareketlerini, ziyaret kayıtlarını, bu tarayıcının yerel müşteri/sepet kopyasını ve yedeklenebilen bildirim görsellerini birleştirir. Dosyadaki manifest alanları alınan kayıt ve görsel sayılarını gösterir. Görsel alınamayan nesneler hata listesinde gösterilir.

## Güvenlik ve yeniden kurulum

- Supabase publishable key web istemcisine ait genel anahtardır ve kaynakta bulunabilir.
- **service_role key, VAPID private key, ORDER_PUSH_HOOK_SECRET, Netlify gizli değişkenleri ve yönetici parolaları pakete dahil edilmez.**
- Bunlar Supabase/Netlify kontrol panellerinde tutulmalıdır; bu dosyalara veya GitHub'a yazmayın.
- Push abonelikleri bilgisayara/telefona bağlıdır. Yeni cihazda tarayıcı bildirim iznini yeniden vermelisiniz.
- Android uygulama kaynakları pakete dahildir. Android uygulamasını aynı uygulama imzasıyla güncellemek için ilk APK'nın imzalama anahtarı ayrıca güvenli olarak saklanmış olmalıdır; bu anahtar bu pakete dahil değildir.

## Proje bilgisi

- Site: https://yemektadinda.com
- GitHub: https://github.com/volkiden06-wq/lezzet-cepte
- Supabase project ref: `jlpqdjhxdpmighnpebkj`
- Bölge: `eu-north-1`

## SQL tam yedek fonksiyonu

`supabase/admin-full-backup.sql`, mevcut şema kurulduktan sonra yöneticiye özel tam JSON yedek RPC'sini kurar. Bu fonksiyonun içeriği mevcut Supabase projesine uygulanmıştır.
