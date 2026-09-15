# Sürüm notları

## 5.1.3 — 6 Eylül 2026

- Yeni: UYGULAMA İÇİ klasör seçici — yalnız MÜZİK İÇEREN klasörler
  listelenir (MediaStore'dan); satıra dokunup klasöre girilir, kutucukla
  tek ya da çoklu seçilir ("Klasörü Ekle" / "4 Klasörü Ekle"). Geri
  tuşu bir üst klasöre çıkar, en başta ekran kapanır. Sistemin "içine
  gir, bu klasörü kullan" akışı tarihe karıştı (izin verilmediyse
  seçenek olarak kalır). "Müzik Dosyalarından" seçeneği (numaralı
  klasör bug'ının kaynağı) tamamen kaldırıldı.
- Yeni: "Tüm dosyalara erişim" izni — etiket yazma, klasör adlandırma
  ve klasör tarayıcı bu tek izinle sorunsuz çalışır; başarısızlıkta
  nedeni ve "İzin Ver" düğmesini içeren diyalog çıkar.
- Düzeltme: yazma/adlandırma izin verildikten sonra DOĞRUDAN dosyaya
  işler (MediaStore dolambaçı yok); "Tümünü Tara" sonucu artık kutuyla
  bildirilir ("Kütüphane güncel." dahil).
- Düzeltme: Favoriler sekmesine paylaş düğmesi eklendi (yalnız orada;
  seçim gerekmez, doğrudan sorar: ayrı dosyalar mı ZIP mi). Daha önce
  yanlışlıkla seçim aksiyonlarına girmişti — düzeltildi.
- İyileştirme: paylaşım sheet'inde ✓ işareti kalktı; "hazırlanıyor"
  penceresi AYRI dosyalar yolunda da döner göstergeyle gelir.
- Düzeltme: tüm alt pencereler (menü/panel) sistem gezinme çubuğunun
  ÜSTÜNDE kalır (SafeArea).
- İyileştirme: seçim başlığının yanındaki boş alana dokununca da seçim
  kapanır; Ayarlar başlığında logo; liste ekleme ekranında atmosfer
  zemini (renk sıçraması bitti); akıllı liste kartlarında ikon rozeti.
- Düzeltme: kuyruğun sonunda ileri oku kaybolup yıldız/çarpı yer
  değiştirmiş gibi görünüyordu — ileri düğmesi artık HER ZAMAN görünür;
  sonda basılınca kuyruğun BAŞINA sarar. (Uygulama içi çubuğun özgün
  düzeni korundu: ✕ · başlık · ★ · çal/duraklat.)
- Düzeltme: "Dosyaya yaz" zinciri sağlamlaştırıldı — MediaStore dosyayı
  tanımıyorsa önce taranıp yeniden denenir; izin sonrası yazım asla
  çökmez; MP4/M4A yazıcı 64-bit atomlu dosyaları da anlar. Başarısızlık
  mesajı artık kısa ve sakin: "Dosyaya yazılamadı. Tekrar dene."
- Düzeltme: bildirim çubuğunda ★ solda, ✕ sağda — sistem bildirimiyle
  aynı düzen.
- Yeni: butonlarda hafif dokunuş animasyonu (basılınca minicik küçülür,
  bırakınca yumuşakça döner) — seçim çubuğu, Kaydet, Tümünü Tara, Liste
  Oluştur. Sekme değişiminde kısa bir soluklanma geçişi (sekmelerin
  durumu korunur).
- Yeni: çoklu paylaşımda biçim seçimi — "Ayrı Ses Dosyaları" (tek tuşla
  açılır) ya da "Tek ZIP Dosyası" (toplu, düzenli). ZIP seçilirse
  "'X.zip' hazırlanıyor…" penceresi döner göstergeyle gelir.
- Düzeltme: çoklu "uygulamadan ve telefondan sil" artık TEK sistem onayı
  ister (Android 11+) — parmak ağrımaz.
- Düzeltme: klasör içinde silinen şarkı ANINDA listeden düşer (gir-çık
  gerekmez); klasör boşalırsa izlemeden otomatik çıkar ve listeye döner.
- Yeni: klasör ekleme akışı — "Klasör Seç" ya da "Müzik Dosyalarından"
  (şarkıları seç, ana klasörleri otomatik eklenir). Hem Klasörler + hem
  Ayarlar → Kütüphane'den.
- Yeni: Ayarlar → Kütüphane'ye "Klasör Ekle" düğmesi; klasör çiplerine
  dokununca O klasör taranır. Bölüm başlıklarında (i) bilgi işareti —
  dokununca o bölümü sade dille açıklar (Hakkında hariç).
- Yeni: Klasörler sekmesinde "Tümünü Tara" ikonu; klasör ⋮ menüsünde "Bu
  Klasörü Tara". Favoriler sekmesinde "Favorileri Paylaş" düğmesi.
- Düzeltme: listeye/favorilere şarkı ekleme ekranından dönünce arka plan
  rengi sıçraması bitti (ekran artık atmosferin üstünde şeffaf).
- Yeni: ZIP paylaşımı artık "hazırlanıyor" penceresi gösterir — "'Music.zip'
  hazırlanıyor… Şarkılar tek dosyada toplanıyor" + dönen gösterge; parmak
  yolu keser (çift basılamaz), paylaşım hazır olunca açılır.
- Yeni: listelerin sağ kenarında ⋮ menüsü — Yeniden Adlandır (şık ad
  diyaloğu) ve Sil. Silme onayı eskisi gibi.
- Yeni: klasör kartlarında ⋮ menüsü — Yeniden Adlandır (TELEFONDAKİ gerçek
  klasörü adlandırır; şarkı/liste yolları otomatik yeni yola taşınır) ve
  Kaldır. Android izin vermezse dürüstçe söyler.
- Tasarım: Ayarlar ekranı yeniden kuruldu — bölüm başlıkları ikonlu,
  temalar ve yedek görsel DOKUNULABİLİR kartlar (seçili olan turuncu
  vurgulu + onay işaretli), kütüphane kartında klasör çipleri + "Şimdi
  tara" düğmesi, ikonlu rozetler; tüm işlevler aynen korundu.
- İyileştirme: Rapor başlıkları yumuşadı ("En Çok Dinlenenler" gibi);
  Favoriler/Listeler boş ekran ikonları yumuşak rozetlere taşındı.
- Düzeltme: mini oynatıcının bildirimden "uçması" GERÇEKTEN bitti — kutu
  ile mini rayı birbirini besleyip birlikte tırmanıyordu (geri besleme
  döngüsü). Artık kutu gelince mini, seçim modundaki AYNISİNİ yapıyor:
  gizlenir; kutu kapanınca geri döner.
- İyileştirme: kutu sürükleme fiziği — parmağı canlı izler (aşağı ve
  yukarı), yeterince itilince parmak kalkmadan kapanır, hızlı savurunca
  kapanır, az itilirse yaylanıp yerine döner.
- Yeni: çoklu paylaşım artık adlı ZIP — klasör paylaşırsa "Music.zip",
  liste paylaşırsa "Selam.zip", seçimle paylaşırsa "5 şarkı.zip". Tek
  şarkı düz dosya olarak gider. Boş klasör/liste paylaşımı bilgilendirir.
- Yeni: M4A/MP4 etiket yazımı — başlık/sanatçı/albüm/kapak artık
  dosyanın içine (moov/udta/meta/ilst) yazılır; "yalnızca uygulamada
  görünür" dönemi bitti. Yazım, MP3 yolundaki yedekli native kanaldan
  geçer; yarıda kalırsa dosya geri yüklenir.
- İyileştirme: "Kapağı kaldır" belirginleşti (turuncu çerçeve); kaldırınca
  veya yeni kapak seçince "Geri al" olur — basınca özgün kapak döner.
- Yeni: kütüphane biçimlerine OPUS, OGA ve AMR eklendi.
- Düzeltme: mini oynatıcının kutudan "uçması" KÖKTEN bitti — kutu ekran
  koordinatında, mini gövde koordinatında hesaplıyordu; artık hepsi tek
  ölçekte: mini yalnız kutunun hemen üstüne süzülür.
- İyileştirme: bildirim kutusu etkileşimi sadeleşti — hızlı dokunuş hiçbir
  şey yapmaz (kalan süre devam eder), basılı tutma süreyi durdurur (bırakınca
  0,7 sn), aşağı itince kapanır.
- Düzeltme: sekme değiştirince tüm seçim modları otomatik biter — mini
  oynatıcı anında geri döner (seçim açıkken sekme değiştirip kaybolması bitti).
- Yeni: "n şarkı/klasör/liste seçildi" başlığına dokununca seçim kapanır;
  Klasörler sekmesi artık klasör sayısını başlıkta gösteriyor.
- Yeni: klasör/liste seçim çubuklarına PAYLAŞ — seçili klasörlerin/listelerin
  tüm şarkıları tek paylaşımda gider (ACTION_SEND_MULTIPLE). Akıllı listeye
  uzun basınca "Listeyi Paylaş" geliyor.
- Tasarım: Dosya bilgileri ekranı yeniden tasarlandı — gölgeli büyük kapak
  + düzen rozeti, biçim/boyut çipleri, tek etiket kartı, M4A'ya göre
  uyarlanan kaydet düğmesi.
- Düzeltme: bildirim kutusu sekmelerin İÇİNE değil KÖK katmana açılıyor —
  mini oynatıcının "uçup kaybolması" bitti; kutu gelince mini sadece
  yukarı kayıp yer açar, kapanınca döner.
- Düzeltme: bildirim kutusuna HIZLI dokunmak artık tepki vermez (kalan
  süresinden devam eder); gerçek TUTMA süre durdurur, bırakınca 0,7 sn
  sonra kapanır; aşağı çekince kapanır.
- Değişiklik: seçim çubuğu ekrana göre daraldı — Şarkılar, klasör içi ve
  akıllı liste içi seçimlerinde yalnız Paylaş + Sil; liste detayında
  Listeden Çıkar + Paylaş + Sil; Favoriler'de Çıkar + Paylaş + Sil.
  (Favorilere/listeye ekleme yalnız ⋮ menüsünde.)
- İyileştirme: "n klasör/liste seçildi" çubukları artık yüzen kapsül —
  alttaki sekmelere bitişik değil.
- Düzeltme: bildirim kutusundaki sarı altı çizgi bitti; kutu parmakla
  aşağı İTİLEREK kapatılabilir; menü/sheet açıkken bekleyip kapanınca
  görünür (menünün üstüne binmez); sekmelerin ve seçim çubuğunun üstüne
  binmez.
- Düzeltme: mini oynatıcı bildirim kutusuyla ARTIK TEMAS ETMEZ — kutu
  üstteyse kendini yeterince yukarı alır (eski sabit-72px kaydırma kalktı).
- Yeni: ⋮ menüsündeki favori ekle/çıkar, "Sadece Uygulamadan Sil" ve mini
  çubuktaki ★ artık bildirim kutusuyla konuşur (daha önce sessizdi).
- Metin turu: ham hata mesajları (İngilizce istisna + dosya yolu) insan
  diline çevrildi; "Motor hazırlanıyor", "Media3", "ID3 etiketi" gibi
  geliştirici dili kaldırıldı; sayı cümleleri akıllandı ("Bir şarkı
  silindi."); metinler "sen" diline tamamlandı.
- Tasarım dizgesi: animasyon süreleri tek standartta (240 ms), köşe
  yarıçapları 3 basamaklı ölçeğe (8/16/20) indirildi; cobble_style.dart
  dizge dosyası eklendi.
- Yeni: bildirim kutusu canlandı — yumuşak animasyonla açılır/kapanır;
  parmak üstündeyken süre durur, bıraktıktan 0,7 sn sonra kaybolur;
  seçim çubuğunun ÜSTÜNDE konumlanır (çubuğu kapatmaz); mini oynatıcı
  gizlenmeyip yukarı kayarak yer açar.
- Düzeltme: favorilere ekleme/çıkarma akıllandı — zaten favoride olan
  eklenmez, olmayan çıkarılmaz; "Bir şarkı favorilere eklendi. Diğeri
  zaten vardı." gibi durumu anlatır. (Eski kod, "Çıkar"da favori
  olmayanı sessizce favoriye EKLİYORDU.)
- Düzeltme: "Listeye ekle" akıllandı — zaten listede olan eklenmez ve
  söylenir. Tek şarkıda büyük tuzak kapandı: listede olan şarkıyı
  "ekle" deyince sessizce LİSTEDEN ÇIKARIYORDU.
- Yeni: uygulama genelinde tek şık bildirim tasarımı — yüzen, yuvarlak,
  ikonlu ve vurgu renkli (ekleme turuncu, silme/hata kırmızı, onay
  tamamlanma işareti). Tüm "eklendi / silindi / hata" cümleleri bu
  tasarımla gösterilir.
- İyileştirme: kayan şarkı adı kesintisiz akar — duraklama ve başa dönüş
  yok; metin soldan çıkıp sağdan girer (sonsuz döngü).
- İyileştirme: seçim çubuğundaki uzun etiketler ("Favorilerden Çıkar")
  taşmaz, sığana kadar ölçeklenir.
- İyileştirme: "+" ile ekleme mesajları açıklayıcı: "Dosya zaten listede",
  "Dosyalar zaten listede", "3 dosya zaten listedeydi. 2 şarkı eklendi.",
  "5 şarkı eklendi".
- Düzeltme: "+" ile yeniden eklenen şarkı kütüphaneye İKİNCİ KEZ ekleniyor,
  klonlar oluşuyor ve birini seçince tüm klonlar seçiliyordu. Artık zaten
  var olan şarkı (aynı ad + boyut) listeye tekrar düşmez; mevcut klonlar
  açılışta otomatik birleşir.
- Düzeltme: şarkı adındaki kayan yazı YALNIZCA o şarkı çalarken kayar
  (diğerleri sade, göz yormaz).
- Düzeltme: "Çıkar" aksiyonu Favoriler sekmesinde kısa, başka yerlerde
  "Favorilerden Çıkar" olarak açık yazılır.
- Düzeltme: seçim modu açıkken uzun basma seçimi SIFIRLAMAK yerine seçime
  ekler — aratıp aratıp seçme akışı artık kesintisiz.
- Düzeltme: boş alana dokununca seçim kapanır — Favoriler, Listeler ve
  Klasörler sekmelerinde de dahil her yerde.
- Düzeltme: seçim modu ve ⋮ menüsü artık AYNI ANDA açılamaz; ⋮'ye basınca
  seçim kapanır, menü güncel durumla açılır (eski "Favorilerden Çıkar"
  takılması bitti).
- Yeni: mini oynatıcı üstüne açılan TÜM menülerden (⋮, diyaloglar, alt
  sayfalar) otomatik kaçar; menü kapanınca geri döner.
- Düzeltme: tema değişince Klasörler/Akıllı listeler sekmeleri ve klasör
  içi ekran eski temada kalıyordu; artık canlı güncellenir.
- Düzeltme: klasör içi ve akıllı liste ekranları açılmıyordu (beyaz ekran) —
  mini oynatıcı sarmalamasındaki yerleşim hatası; ayrıca o ekranlarda alt
  gezinme çubuğu artık görünür kalır (detaylar sekme çerçevesinde açılır).
- Yeni: mini oynatıcı seçim modundan otomatik KAÇAR — "n şarkı seçildi"
  çubuğu ya da klasör/liste seçim çubuğu açılınca kayarak iner, seçim
  bitince geri döner.
- Düzeltme: klasör ve liste çoklu seçimi canlı görünmüyor, Vazgeç
  tepki vermiyordu; seçim çubukları düz/tam genişlik tasarımına geçti.
- Düzeltme: favoriye eklenmiş şarkılar seçilince ilk aksiyon "Favori"
  yerine "Çıkar" olur (akıllı; favoriler sekmesinde dahi).
- Düzeltme: "Sadece Uygulamadan Sil" ikonu sarı (telefondan silme kırmızı).
- Düzeltme: rapor ekranının zemini temayla senkron (koyu katman kalktı).
- Düzeltme: uygulama içi sürüm göstergesi 5.1.3 (5.1 kaliyordu).
- Yeni: uzun şarkı adları artık KAYAR (liste, mini oynatıcı, Şimdi Çalıyor) —
  kesik "..." yerine modern çalar standardı.
- Düzeltme: "+" ile yeniden eklenen şarkı, numaralı/sayısal garip bir klasöre
  düşebiliyordu. Artık izlenen klasörlerde gerçek konumu bulunur ve şarkı
  KENDİ klasörüne kabul edilir; bulunamazsa uygulama içine alınır (sayısal
  klasör görünümü bitti).
- Düzeltme: mini oynatıcı ✕ ile kapatılıp uygulama yeniden açıldığında
  "son çalınan" boş kaydedildiği için çalar kütüphanenin ilk şarkısına
  düşüyordu. Boş kuyruk artık son kaydı silmez.
- Düzeltme: geri tuşu uygulamayı kapatmıyordu/kapatıyordu — artık önce
  seçim modundan çıkar, gerekirse uygulama arka plana geçer (kapanmaz).
- İyileştirme: mini oynatıcı klasör içi ve akıllı liste ekranlarında da
  görünür.
- İyileştirme: seçim modu — Favoriler sekmesinde "Çıkar", liste içinde
  "Listeden Çıkar" aksiyonları; "Liste" aksiyonu ⋮ menüsündekiyle aynı
  diyaloğu açar; favori simgesi her yerde yıldız; seçim çubuğu yüzen,
  yuvarlatılmış, animasyonlu ve mini oynatıcının ÜSTÜNDE durur; "Tümünü
  seç" her ekranda görünür; seçim arama değişse de KORUNUR (aratıp
  aratıp seçilir); boş alana dokunmak seçimden çıkarır; Listeler
  sekmesinde listeler, Klasörler sekmesinde klasörler de çoklu seçilip
  toplu kaldırılabilir; "Sadece Uygulamadan Sil" sarı, "telefondan sil"
  kırmızı ikonla her menüde aynı.
- **Yeni: Çoklu seçim.** Her şarkı listesinde (Şarkılar, Favoriler, çalma
  listeleri, klasör içi, akıllı listeler — arama sonuçlarında dahi): şarkıya
  basılı tut ile seç, dokunarak çoğalt. Alt çubuktan: Favorilere ekle,
  listeye ekle (yeni liste kurarak dahil), paylaş, sil (yalnızca uygulamadan
  ya da uygulama + telefondan; toplu tek onay ile).
- Düzeltme: arama sonuçlarından şarkı çalınca kuyruk yalnızca arama
  sonucunu değil, ARANAN LİSTENİN TAMAMINI baz alıyor — ileri/geri,
 listenin sıradaki şarkısına gider (klasör/liste/favoriler/akıllı dahil).
- Düzeltme: aynı şarkı ikinci kez eklenemiyor. "+" ile eklenen dosya,
  kütüphanede aynı ad + boyut varsa kopyalanmadan mevcut kayda düşer;
  numaralı ikinci kopya üretimi bitti. Klasör eklerken yol yazımı
  farkları (/sdcard = /storage/emulated/0) eşitlenir; ortak şarkılar bir
  kez gösterilir (küme birleşimi). Açılışta mevcut çift kayıtlar
  onarılır — favoriler ve liste üyelikleri kalan kayda aktarılır.
  (Çalma listeleri serbesttir: aynı şarkı birden çok listede bulunabilir.)
- Düzeltme: haftalık rapor, tamamlanan hafta için bir kez kilitlendikten
  sonra aynı haftanın verisi değişse bile (tarih/saat düzeltmesi, yedek
  dönüşü) eski hâlini gösteriyordu. Artık kilitli haftanın çalma/saniye
  verisi değişmişse rapor güncel veriyle yeniden üretilir; normal
  kullanımda (hafta verisi değişmez) davranış aynıdır.
- Düzeltme: Android Auto'da direksiyondan ileri/geri ve parça sonunda AYNI
  şarkıya başa sarma: Auto'nun arka plan sorguları kardeş-kuyruk kurulumunu
  bozabiliyordu (tek şarkılık kuyruk + "tümünü tekrarla" = aynı şarkı
  döngüsü). Kuyruk kurulumu artık kademeli ve deterministik: gezinilen
  listenin kardeşleri → şarkının kendi klasörü → tüm kütüphane.
- **Yeni: M4A/MP4 etiket desteği.** YouTube kaynaklı M4A'lar dahil,
  başlık/sanatçı/albüm (©nam/©ART/©alb) ve albüm kapağı (covr) artık
  okunuyor — liste, Şimdi Çalıyor, bildirim ve Android Auto'da görünür.
  M4A'da "dosyaya yaz" yok; düzenlemeler yalnızca uygulama içinde kaydedilir.
- Düzeltme: bazı MP3'lerde orijinal albüm kapağı görünmüyordu (taş/nota
  düşüyordu). Üç ayrı neden birden kapatıldı:
  • Kapak okuyucu, etiket başlığındaki "genişletilmiş başlık"ı atlamıyordu
    (isim okuyucu atlıyordu; kapak okuyucu atlamıyordu → kayma)
  • ID3v2.2 etiketli eski dosyalardaki "PIC" karesi hiç desteklenmiyordu
    (artık hem uygulama içinde hem bildirimde okunur)
  • 2 MB üzeri etiketli dosyalarda kapak araması yarıda kesiliyordu
    (tavan 8 MB'a çıkarıldı)
- Düzeltme: "Dosya bilgileri"nden yalnızca isim düzenlenirse kapak önbelleği
  eskide kalıyordu; artık yeniden çıkarılır
- İyileştirme: kapak önbelleği Flutter ve Android (bildirim/Auto) tarafında
  tek dizinde birleştirildi — çifte çıkarma ve "kapağı gizle" sonrası
  bildirimde eski kapak kalması sorunu bitti
- Test: v2.2 ve genişletilmiş başlık için 4 yeni birim testi

## 5.1.1 — 5 Eylül 2026

- Düzeltme: “Sadece Uygulamadan Sil” sonrası şarkı, uygulamayı kapatıp
  açınca otomatik taramayla geri geliyordu. Artık yalnızca
  Ayarlar → “Şimdi tara” geri getirir.
- Düzeltme: tüm kuyruk çalınamadığında (SD kart çekilmiş / dosya taşınmış)
  sonsuz hata-atlama döngüsü kuruluyordu; 5. ardışık hatada çalma durur.
- İyileştirme: büyük kütüphanelerde şarkıya basınca UI takılması — kuyruk
  JSON okuma/parse ve MediaItem üretimi artık arka plan iş parçacığında.
- İyileştirme: Android 7–9'da etiket yazma / telefondan silme için eksik
  olan depolama izni artık çalışma zamanında isteniyor; Android 10'da
  silme, sistem onay diyaloğuyla düzgün tamamlanıyor.
- İyileştirme: durum yayını çalarken 400 ms, duraklarken 1.5 sn (pil).
- İyileştirme: hata günlüğü 256 KB üzerine çıkınca kırpılıyor.
- İyileştirme: key.properties yoksa release derleme DEBUG imzaya sessizce
  düşmüyor — uyarı verip duruyor (`-PdebugSigning` ile geçilebilir).
- Temizlik: kaldırılmış widget kodu kalıntıları silindi.

## 5.1.0 — 31 Ağustos 2026

- Android Auto: MediaLibraryService — Şarkılar, Albümler, Sanatçılar, Klasörler, Listeler, Favoriler, Akıllı
- Müzik çalar kimliği: `APP_MUSIC`, `MUSIC_PLAYER`, `MEDIA_PLAY_FROM_SEARCH`
- Akıllı listeler 4. sekme: En çok / Az / Hiç (Pazartesi raporuna kilitli)
- Haftalık rapor (Pazartesi–Pazar, Pazartesi 09:00 bildirim)
- 10 bant ekolayzer + bas + sanallaştırıcı (perde yok)
- Widget, parça kes / zil, uygulama-içi kapak kaydı kaldırıldı
- Dosya bilgileri: yalnızca dosyaya yaz
- Bildirimde ★ ve kapat (X); duraklatınca bildirim kalır
- Son şarkıda sonraki başa döner; karıştır / tekrarla kalıcı
- Hızlı şarkı değiştirince çökme düzeltildi

## 5.0 — 29 Ağustos 2026

- Panel kutucuğu kaldırıldı
- Uygulama açılınca boş “Çalıyor” bildirimi yok
- Bildirim ✕: müzik durur, yeniden başlamaz; mini de kapanır
- Mini ✕: kapanır kalır (git-gel yok)
- Basılan şarkı kuyruk kurulmadan hemen çalar (listedeki ilk parça dahil)
- Dosyalar’dan MP3: uygulamayı açar ve çalar

## 4.2.10 — 29 Ağustos 2026

- Panel kutucuğu: yalnızca uygulamayı açar (müzik başlatmaz)
- Dosyalar MP3: 5 sn FGS çökmesi düzeltildi; medya bildirimi çıksın
- Yavaş MP3: JPEG’i MPEG sanan tarama kaldırıldı (Bu şarkı açılamadı)
- Kutucuk simgesi: turuncu kare + play

## 4.2.9 — 29 Ağustos 2026

- Dosyalar MP3: Flutter açılmaz; bildirim kutusu. Kutuya basınca uygulama, çalma devam
- Mini: native currentPath her tikte; splash öncesi bağlanma
- Listeler paleti setState dinleyicisi
- ID3: ardışık etiket + MPEG senkron; atlama önbelleği
- Kutucuk: sistem “ekle” isteği + drawable ikon
- Eski VIEW varsayılanı MainActivity’ye gelse bile UI kapanır

## 4.2.8 — 29 Ağustos 2026

- ID3 atlama: FileDataSource final, sarmalayıcı (derleme)
- Listeler: gece/gündüz paleti çık-gir olmadan yenilenir
- Uygulama kapanınca müzik sürüyorsa mini, açılışta native oturumdan döner
- Hızlı ayarlar kutucuğu (Cobble logosu; Samsung’da Modlar yanına eklenir)
- Dosyalar’dan MP3: uygulama UI’si açılmaz, bildirimde çalar
- Büyük kütüphane: kuyruk Binder yerine dosyadan; kapak her öğeye basılmaz

## 4.2.7 — 29 Ağustos 2026

- Büyük ID3 kapaklı MP3’lerde atlama: etiket gövdesi okunmadan atlanır

## 4.2.6 — 29 Ağustos 2026

- Listeler / Favoriler AppBar `+` (liste doluyken de ekleme)
- Mini oynatıcı setQueue sırasında kaybolmaz; gerçek hatada snackbar
- Play/pause ikonu buffering’de zıplamaz
- Kütüphane JSON dosyasına (prefs 1 MB tavanı yok); mevcut veri taşınır
- Klasör taraması: MediaStore + ön plan (dataSync) + wake lock; ID3 sonra; ara kayıt
- MP3 atlama: ID3 kapak okunmaz, sıradaki parça önceden buffer

## 4.2.5 — 28 Ağustos 2026

- Mini oynatıcı Şarkılar, Favoriler ve çalma listesi içinde (Ayarlar’da yok)
- Kaynak etiketi: Favoriler / liste adı; Şarkılar’dan çalınca yok
- Mini ✕: müzik durur, bildirim kapanır
- Mini’ye dokununca Şimdi Çalıyor

## 4.2.4

- Parçayı paylaş (WhatsApp vb.)
- Dosya bilgileri + paylaş Şarkılar ⋮ menüsünde
- Orijinal albüm kapağı kullanılmaz; kullanıcı kapağı veya nota
- Canlı bildirim kapağı sabit (üç taş)
- Sabit satır yüksekliği
- Hız paneli gizli (1× butonu)
- Önceki parça tek basışta
- Rapordan yenile/temizle kalktı

## 4.2.3

- Uygulama logosu L (turuncu C + play + nota)
- Bildirim küçük ikon

## 4.2.2

- Hız kaydırıcısı; kayıt yalnızca bırakınca
- Düzeltme: "İzin Ver" artık HER durumda bir sayfa açar — bazı
  Samsung'lar pakete özel izin sayfasını açmıyordu; sırayla deneniyor:
  uygulamanın izin sayfası → genel "tüm dosyalara erişim" listesi →
  uygulama bilgisi. Ayarlardan dönünce sonuç kutuyla söylenir; klasör
  akışında izin verilirse seçici DOĞRUDAN açılır.
- Düzeltme: yazma/adlandırma hatasında izin zaten AÇIKSA "izin
  gerekiyor" denmez (yanıltıcıydı) — dürüst ve sakin hata bildirilir.
  Doğrudan yazma başarısız olsa bile MediaStore yolu denenir.
- Düzeltme: liste sayaçları — şarkı silinince (her iki silme
  seçeneğinde de) yolu TÜM listelerden ve favorilerden süpürülür;
  sayaç ayrıca yalnız kütüphanede VAR OLAN şarkıları sayar (eski
  kayıtlardaki hayalet yollar da artık sayılmaz).
- İyileştirme: dosya bilgilerinde boş bir yere dokununca klavye
  kapanır, imleç kalkar.
- İyileştirme: listeye şarkı ekleme ekranı yenilendi — kapaklı
  satırlar, yuvarlak işaret kutuları, alçalan "Kaydet" düğmesi ve
  seçili sayacı (klasör seçiciyle aynı dil).
- Yeni: klasör seçici artık GERÇEK bir müzik seçici — klasöre dokununca
  İÇİ AÇILIR: alt klasörler ve ŞARKILAR kapaklarıyla listelenir. Şarkıya
  dokun = tek tek seç; klasörü basılı tut = klasörü seç; boşluğa dokun
  ya da ✕ = seçimden çık; Tümünü seç görünür her şeyi ekler. Alt düğme
  seçime göre adlanır: "Klasörü Ekle" / "4 Klasörü Ekle" / "Şarkıyı
  Ekle" / "3 Şarkı Ekle" / "2 Klasör + 5 Şarkı Ekle".
- Yeni: klasör eklemeden tek tek şarkı ekleme — istediğin klasöre gir,
  şarkıları seç, ekle. Şarkılar sekmesindeki + (dosya seçici) bu yüzden
  KALDIRILDI; müzik ekleme tek yerden: sağ üstteki klasör simgesi.
- Düzeltme: ekleme özetleri her koşulda düzgün Türkçe kurulur: "Klasör
  eklendi, 20 şarkı alındı. 7 tanesi zaten kütüphanedeydi.", "3 klasör
  eklendi, 64 şarkı alındı. Diğer ikisi zaten izleniyordu.", "Bu klasör
  zaten izleniyor." (tekil/çoğul karışması bitti).
- Düzeltme: "Dosyaya yaz" zinciri — boyut %90 tablosu yüzünden başarılı
  yazım başarısız sanılabiliyordu (tam eşitlik geldi); "tüm dosyalara
  erişim" varken gereksiz sistem dosya-onay diyalogu çıkmıyor (URI ile
  doğrudan, yedekli yazma); hata iletisi sakin: "Dosyaya yazılamadı.
  Tekrar dene."
- Düzeltme: tema (atmosfer) animasyonu bazen donuyordu — saat tik-tik'
  i başlangıçta hiç başlatılmamış, yalnızca uygulamayı arka plana
  alıp döndürünce başlıyordu. Artık açılışta akar.
- Düzeltme: ekran arası geçişlerde tema "sıçraması" — tüm atmosfer
  katmanları artık AYNI saati paylaşır (fazlar hep eş); klasör
  seçici ve liste detayı saydam zeminli oldu, şarkı ekleme ekranı
  alttaki atmosferi kullanır. Klasör seçiciden/Liste detayından/
  şarkı eklemeden dönüşte renk atlaması bitti.
- İyileştirme: klasör seçicide klasör geçişlerine hafif kayma + solma
  animasyonu geldi; listenin son satırı sistem gezinme çubuğunun
  altında kalmaz; seçim BOŞALINCA seçim modu kendiliğinden biter;
  GERİ tuşu seçim modundaysa önce seçimi bırakır (klasörlerden
  çıkmaz); listenin başında küçük bir kullanım ipucu satırı:
  "Şarkıya dokun: seçim · Klasörü basılı tut: klasörü seç".
- İyileştirme: Şarkılar sekmesinde klasör simgesi rapor düğmesinin
  SOLUNA alındı; "Henüz şarkı yok" ve "Sonuç bulunamadı" metinleri
  düzgünce ortalandı.
- Yeni: Listeler sekmesinde ⋮ menüsüne "Şarkı Ekle" ve "Paylaş"
  seçenekleri eklendi (artık liste adına basılı tutmak zorunda
  değilsin).
- Düzeltme: ekleme özetleri — zaten izlenen klasörler de YENİDEN
  TARANIR (uygulamadan silinmiş şarkılar geri gelir) ve özetler
  klasör ADI verir: '"Music" eklendi, 20 şarkı alındı. 7 tanesi
  zaten kütüphanedeydi.', '"Music" zaten izleniyordu — 5 şarkı geri
  eklendi.', '"Music" zaten izleniyor.'
- Düzeltme: KÖKLÜ — tema karışması/siyah koyulaşma. İç ekranlar (klasör
  seçici, liste detayı, şarkı ekleme, akıllı liste detayı, klasör
  şarkıları, dosya bilgileri, rapor) saydam bırakılınca altlarında
  ana ekran değil SİYAH bir zemin görünüyordu (Flutter alt rotayı
  çizmez); gece temasında siyah uyduğu için fark edilmiyordu. Artık
  her iç ekran kendi temalı zeminini + atmosferini taşır — gündüz,
  otomatik, hepsinde geçiş akıcı.
- Düzeltme: paylaşımda "donup bekliyor" — ZIP oluşturma ve dosya
  kopyalama ANA iş parçacığında çalışıyordu; arayüz ve döner gösterge
  bile donuyordu. Artık ağır iş arka planda; "hazırlanıyor" penceresi
  akar ve ne olduğunu söyler ("X.zip hazırlanıyor… — Şarkılar tek
  dosyada toplanıyor").
- Düzeltme: boş listeyi ⋮ menüsünden paylaşınca hiçbir şey olmuyordu —
  artık "Paylaşılacak şarkı yok." kutusu çıkar (her paylaşım yolunda).
- Yeni: Ayarlar → Kütüphane'ye "Klasör Seçici" tercihi: Uygulama İçi /
  Sistem — istediğin zaman değiştirilir. Ayrıca "Son tarama" satırı
  kaldırıldı.
- Yeni: Klasörler sekmesinde ⋮ menüye "Paylaş" eklendi (klasördeki
  şarkıların tamamı). Akıllı listelere ⋮ menüsü eklendi (yalnız Paylaş).
- Değişiklik: akıllı listelerde basılı tutunca doğrudan paylaşım
  sayfası açılmaz artık — listelerdeki gibi SEÇİM MODU gelir (yalnız
  Paylaş düğmesi); boşken Paylaş'a basınca "Paylaşılacak şarkı yok."
  denir. Seçim boşluğa dokununca/✕ ile kapanır, sekme değişince biter.
- İyileştirme: klasör seçicide kullanım ipucu satırı ("Şarkıya dokun:
  seçim · Klasörü basılı tut: klasörü seç") seçim modunda da görünür.
- Düzeltme: klasör içinden "Sadece Uygulamadan Sil" sonrası şarkı ekranda
  kalıyordu — liste, dinleyicinin DIŞINDA bir kez hesaplanıp esir
  düşürülüyordu; dinleyicide bile eski liste yeniden çiziliyordu. Artık
  liste her çizimde canlı okunur; silinen anında düşer (çık-gir gerekmez).
- Düzeltme: "Dosyaya yaz" — "Tüm dosyalara erişim" verilmişse yazım artık
  DOĞRUDAN Dart tarafından yapılır (native kopya/MediaStore zinciri
  tamamen atlanır; en az kırılgan yol) ve başarıdan sonra medya kitaplığı
  tazelenir. Native yol yedek olarak durur.
- Düzeltme: iç ekranlardan geri dönüşte kalan tema sıçraması — kaydırmalı
  geçişte iki atmosfer katmanı üst üste kayıp "çift görüntü" oluşturuyordu;
  iç ekran geçişleri yumuşak solmaya çevrildi (liste detayı, şarkı ekleme,
  akıllı detay, klasör içi, dosya bilgileri, rapor, klasör seçici).
- Yeni: Ayarlar'da ayrı "Klasör Seçici" bölümü — (i) rozetiyle iki
  seçenek açıklanır: "Cobblestone Seçici" (klasörlere gir, şarkıları
  görerek seç) ve "Sistemin kendi seçicisi" (Android'in klasör ekranı).
- Düzeltme (KÖKLÜ): "Dosyaya yaz" — doğrudan Dart yazımı artık izin
  KOŞULSUZ önce denenir (iki deneme + kısa bekleme), başarısız olursa
  native zinciri devralır. HER başarısızlıkta neden kayda geçer
  (hata_gunlugu.txt) ve kullanıcıya söylenir: m4a biçimi desteklemiyorsa
  "Bu dosyanın biçimi (m4a) etiket yazımını desteklemiyor…", dosya
  yoksa, izin yoksa — artık sebebi belli. Belirsiz "yazılamadı" bitti.
- Yeni: Ayarlar → Kütüphane — izlenen klasörler artık minik çipler
  değil KART listesi: klasör adı, şarkı sayısı (canlı), yeniden tara ve
  UYGULAMADAN KALDIR düğmesi (onay ister; telefondaki dosyalar durur).
- Değişiklik: klasör seçicide jest düzeni — klasöre DOKUN = SEÇ (şarkılarla
  aynı mekanik), BASILI TUT = klasöre gir. İpucu satırı güncellendi.
- Düzeltme: "Dosyaya yaz" strateji zinciri genişletildi — A) doğrudan
  üzerine yaz; B) yanına geçici yaz + ad değiştirme (rename: dosya başka
  bir süreçte açıkken bile geçen, farklı sistem çağrısı yolu); üç tur,
  artan bekleme; ardından native zinciri (MediaStore URI + sistem onayı).
  Hata olursa kutu artık NEDENİ yazıyor (errno dahil) ve hata günlüğüne
  "dosyaya_yaz" kaydı düşüyor — bir dahaki denemede teşhis kesin.
- Düzeltme (ASIL NEDEN BULUNDU): m4a'ya "Dosyaya yaz" HİÇ çalışmıyordu —
  sebebimiz izin ya da MediaStore değil, MP4 metadata kurucunun atom
  adlarını ASCII ile kodlamasıydı: iTunes atom adları '©nam'/'©ART'/
  '©alb' © karakteri içerir, ASCII'de yok → yazım daha dosyaya
  dokunmadan "Invalid argument (string): Contains invalid characters"
  ile çakılıyordu. Atom başlıkları artık Latin-1 ile kodlanıyor.
  (MP3 yolu zaten UTF-8 idi; etkilenmeyen tek yol oydu. Teşhis, hata
  nedenini kullanıcıya gösteren yeni mesaj sistemiyle mümkün oldu.)
