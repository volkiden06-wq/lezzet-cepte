# YEMEK TADINDA – Ürün Kişiselleştirme

## Müşteri tarafı
Ürün için yönetici kişiselleştirmeyi açtığında ürün kartında **ÖZELLEŞTİR** düğmesi görünür. Müşteri:
- İstemediği malzemeleri çıkarabilir.
- Ücretli ekstra malzemeleri seçebilir.
- Özel hazırlama notu yazabilir.
- Sepette seçimlerini görebilir, düzenleyebilir ve adetini değiştirebilir.

Ekstra malzeme fiyatları ürünün başlangıç fiyatına eklenir. Sepet toplamı, sipariş kaydı, WhatsApp mesajı, müşteri sipariş geçmişi ve yönetim sipariş listesinde seçimler gösterilir.

## Yönetici tarafı
1. Yönetim panelinde **Ürün Kişiselleştirme** sayfasını açın.
2. Ürünü seçin.
3. Kişiselleştirmeyi etkinleştirin.
4. Çıkarılabilecek malzemeleri her satıra bir tane gelecek şekilde yazın.
5. Ücretli ekstraları `Malzeme adı|Fiyat` biçiminde yazın. Örnek: `Kaşar peyniri|25`.
6. Hazırlama notu alanını açık veya kapalı seçin.
7. **Ayarları Kaydet ve Tüm Cihazlara Eşitle** düğmesine basın.

## Verilerin korunması
Kişiselleştirme ayarları ayrı bir ürün alanı olarak `site_catalog.products` içindeki mevcut ürün kaydına eklenir. Ürün adı, kimliği, fiyatı, kategorisi, görseli, kampanyaları, müşteri kayıtları ve geçmiş siparişler silinmez veya sıfırlanmaz. Mevcut katalog senkronizasyonu ayarları telefon ve bilgisayara taşır. Tam site yedeği de `site_catalog` ürün verisini içerdiğinden ayarları otomatik kapsar.

Müşterinin seçtiği kişiselleştirme, siparişin `items` JSON verisinde saklanır. Eski sipariş satırlarında kişiselleştirme bulunmuyorsa mevcut kayıtlar aynen çalışır.

## Sunucu tarafı fiyat kontrolü
Ekstra malzemelerin adları ve fiyatları sipariş RPC'sinde güncel ürün ayarlarıyla karşılaştırılır. Müşteri tarayıcısında fiyatı değiştirilmiş bir ekstra, ürün fiyatı veya toplamı sunucu doğrulamasından geçmez. Seçenekler ürün yönetiminden değiştiyse müşterinin sepetini yenilemesi gerekebilir.

## SQL kurulum notu
Mevcut Supabase projesinde işlev güncellemesi zaten uygulanmıştır. Yeni bir proje kurulurken önce temel katalog, sipariş ve sadakat puanı SQL dosyalarını kurun; ardından `supabase/product-customization-order-validation.sql` dosyasını Supabase SQL Editor'de çalıştırın.
