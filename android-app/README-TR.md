# YEMEK TADINDA Android uygulaması

Bu proje, mevcut https://yemektadinda.com web sitesini Android uygulama simgesiyle açan Trusted Web Activity (TWA) kabuğudur.

## Mevcut site korunur

Android uygulaması mevcut web sitesini açar. Ürünler, fotoğraflar, menüler, kampanyalar, siparişler, müşteri abonelikleri ve Supabase kayıtları web sitesinde kalır. Bu Android klasörü bu kayıtları değiştirmez.

Web sitesinde yapılan menü ve kampanya güncellemeleri, uygulama açıldığında otomatik görünür. Android kabuğu için yeni bir APK gerekmez.

## APK

GitHub Actions içindeki "Build YEMEK TADINDA Android APK" iş akışı imzalı APK oluşturur. Alan adı doğrulama dosyası da aynı derlemede oluşturulur.

## Önemli

İlk APK'nın imza anahtarı yalnızca ilk derleme sırasında oluşturulur ve depoya yüklenmez. Bu APK, web içeriği uzaktan geldiği için normal site güncellemelerini almaya devam eder. Android kabuğunda değişiklik yapılması ve aynı uygulamanın üzerine yeni APK kurulması gerekirse kalıcı imzalama anahtarının güvenli şekilde ayrıca saklanması gerekir.
