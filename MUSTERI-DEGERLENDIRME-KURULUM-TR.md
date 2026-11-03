# YEMEK TADINDA – Müşteri Değerlendirmeleri

## Özellikler
- Müşteri, yalnızca kendi telefonuyla eşleşen ve **Teslim edildi** durumundaki siparişlerdeki ürünlere puan verebilir.
- Her sipariş/ürün için bir değerlendirme kaydedilir.
- Puan 1–5 yıldızdır. Yazılı yorum isteğe bağlıdır ve 500 karakterle sınırlıdır.
- Sipariş geçmişindeki arşiv kayıtları da doğrulamada dikkate alınır.
- Yorumlar ilk kayıtta **Bekleyenler** durumundadır. Ürün kartlarında yalnızca yönetici tarafından onaylanan yorumların yıldız ortalaması gösterilir.
- Ürün kartındaki yıldız/yorum bağlantısı onaylanmış yazılı yorumları açar.
- Kampanya içindeki ücretli ekstra ürünler ve ücretsiz hediyeler de sipariş detayında ürün olarak yer alıyorsa değerlendirilebilir.

## Yönetici kullanımı
1. Yönetim paneline giriş yapın.
2. **⭐ Değerlendirmeler** bölümünü açın.
3. **Bekleyenler** sekmesinde yorumu kontrol edin.
4. Uygun yorumu **Onayla ve yayınla** düğmesiyle yayımlayın. Uygun olmayanı reddedin.
5. Yayındaki bir yorumu kaldırmanız gerekirse **Yayından kaldır** seçeneğini kullanın.

## Müşteri kullanımı
1. Sitede **Siparişlerim** bölümünü açın ve siparişte kullanılan telefon numarasını girin.
2. Durumu **Teslim edildi** olan sipariş kartındaki ürünün **DEĞERLENDİR** düğmesine basın.
3. 1–5 yıldız seçin, dilerseniz yorum yazın ve gönderin.
4. Gönderilen değerlendirme yönetici onayından sonra yayımlanır.

## Kurulum / veritabanı
Bu özellik mevcut Supabase projesine ayrı `product_reviews` tablosu ve `submit_product_review` RPC fonksiyonuyla eklenmiştir. Mevcut sipariş, ürün kataloğu, kampanya veya sadakat puanı kayıtları değiştirilmez.

Yeni bir Supabase projesi kurarken önce Supabase SQL Editor'de:
- `supabase/product-reviews.sql`

dosyasını çalıştırın. Tam site yedeği fonksiyonu değerlendirme kayıtlarını da içerir; `supabase/admin-full-backup.sql` dosyasını kurarken ürün değerlendirme SQL dosyasını önce çalıştırın.

## Güvenlik
- Doğrudan anonim INSERT izni verilmez.
- RPC, sipariş numarası + telefon + teslimat durumu + siparişteki ürün kimliğini veritabanı tarafında kontrol eder.
- Tekrarlı sipariş/ürün değerlendirmesi benzersiz kısıtla engellenir.
- Yorum metni, müşteri adı ve ürün adı ekrana basılırken HTML olarak escape edilir.
- Yalnızca onaylanmış yorumlar herkese açık okunabilir.
