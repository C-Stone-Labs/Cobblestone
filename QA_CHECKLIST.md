# Cobblestone v5.1.1 — Test ve Yayın Kontrol Listesi

**Sürüm:** 5.1.1 (versionCode 52) · **Tarih:** 5 Eylül 2026

---

## 1. Bu sürümde değişenler

| # | Tür | Değişiklik |
|---|---|---|
| 1 | 🐛 Hata | "Sadece Uygulamadan Sil" sonrası şarkı, uygulamayı kapatıp açınca otomatik taramayla geri geliyordu. Artık **yalnızca Ayarlar → Şimdi tara** geri getirir (`song_storage.dart` → `markDeleted`). |
| 2 | 🐛 Hata | Kuyruğun tamamı çalınamadığında (SD kart çekildi, dosya taşındı) sonsuz hata-atlama döngüsü: **5 ardışık hatada çalma duraklatılır** (`PlaybackService.kt`). |
| 3 | ⚡ Performans | Kuyruk JSON okuma/parse + MediaItem üretimi (öğe başına File.exists çağrıları) ana thread'den arka plana alındı — büyük kütüphanede şarkıya basınca takılma biter (`MainActivity.kt`). |
| 4 | ⚡ Performans | Durum yayını çalarken 400 ms, duraklarken 1.5 sn. |
| 5 | 🐛 Uyumluluk | Android 7–9: etiket yazma / telefondan silme öncesi WRITE_EXTERNAL_STORAGE artık runtime'da isteniyor. |
| 6 | 🐛 Uyumluluk | Android 10: "telefondan sil", RecoverableSecurityException onay akışıyla düzgün tamamlanıyor. |
| 7 | 🧰 Güvenlik | `key.properties` yoksa release derleme DEBUG imzaya sessizce düşmez — hata verir (`-PdebugSigning` ile bilerek geçilebilir). |
| 8 | 🧰 Bakım | Hata günlüğü 256 KB'ta kırpılır; ölü widget kodu temizlendi. |

---

## 2. Silme senaryosu (asıl düzeltilen bug) — MUTLAKA TEST ET

1. Klasörler sekmesi → klasör seç → tara.
2. Bir şarkı ⋮ → **Sadece Uygulamadan Sil** → listeden gitmeli.
3. Uygulamayı recent'lerden kapat, yeniden aç → şarkı **GELMEMELİ** ✔ (önceden geri geliyordu)
4. Ayarlar → **Şimdi tara** → şarkı **GERİ GELMELİ** ✔
5. Aynı şarkı Dosyalar uygulamasından açılabilir olmalı (dosya diskte duruyor).
6. "Uygulamadan ve Telefondan Sil": Android 11+ sistem onay diyaloğu çıkmalı; onaydan sonra Dosyalar'da da gitmeli.

## 3. Rapor ve Akıllı listeler — kontrol senaryoları

- [ ] Bir şarkıyı 30 sn'den az dinle → çalma SAYILMAMALI (30 sn kuralı; kısa şarkılarda %90).
- [ ] 30 sn+ dinle → Pazartesi–Pazar haftasına işlenmeli.
- [ ] Akıllı sekme: "En çok / Az / Hiç" listeleri geçen haftanın verisini göstermeli (bu haftanınkini değil).
- [ ] Pazartesi 09:00 bildirimi gelmeli → dokununca rapor açılmalı.
- [ ] Bildirimdeki ★ (native) ↔ Favoriler senkron: uygulamadan favoriye ekle → bildirimde yıldız dolu olmalı; bildirimden ★ → uygulamadaki Favoriler güncellenmeli.
- [ ] Telefen yeniden başlatma sonrası Pazartesi alarmı korunmalı (ReportBootReceiver).
- **Bilinen sınırlama:** Uygulama recent'lerden silinir ve yalnızca bildirimden dinlenmeye devam edilirse, o süre rapora işlenmez (Flutter motoru ölür; istatistik Dart tarafında). İleride native'e taşınabilir — yol haritasında.

## 4. Android Auto — kontrol senaryoları

- [ ] Auto kökünde 7 kategori: Şarkılar, Albümler, Sanatçılar, Listeler, Favoriler, Klasörler, Akıllı.
- [ ] Bir klasöre gir → şarkıya bas → **kardeş şarkılar kuyruğa gelmeli** (yalnızca tek şarkı değil).
- [ ] Albüm/sanatçı kapakları tarayıcıda; çalan şarkının kapağı "şimdi çalıyor"ta.
- [ ] "Hey Google, [şarkı] Cobblestone'da ara" → arama sonuçları çalmalı.
- [ ] Direksiyon sonraki/önceki tuşları; son şarkıda "sonraki" başa sarmalı.
- [ ] Araç bağlantısı kesilip geri gelince **son kuyruk kaldığı yerden** devam etmeli (onPlaybackResumption).
- [ ] Duraklatılmış bildirim uygulama kapatılsa da kalmalı; ✕ ile tamamen kapanmalı.

## 5. AAB üretimi (kendi makinende)

```bash
cd cobblestone
flutter upgrade                 # güncel stable — hedef API 36 için şart
flutter pub get
flutter analyze                 # hata: 0 olmalı
flutter test                    # 3 ID3 testi geçmeli
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab  (versionCode 52)
```

`android/key.properties` + `.jks` yerinde olmalı (yoksa derleme bilerek durur).

## 6. Play Console adımları (kapalı testi SİLME!)

1. **Testi silme, sıfırdan başlama:** testçiler ve 14 günlük süreklilik korunur.
   Kişisel hesaplarda üretime geçiş için en az **12 testçi 14 gün aralıksız** gerekir.
2. Kapalı test → iz → **Yeni sürüm** → 52 kodlu AAB'yükle.
   Not: 31 Ağu 2026'dan beri güncellemeler **API 36** hedeflemek zorunda.
3. İzin videosu: App content → ilgili izin bildirimi → düzenle → doğru video → yeniden gönder.
   Batarya iyileştirmesi dışında tutma izni videosunda: Ayarlar → "Arka planda kesilmesin"
   düğmesi → sistem diyaloğu → kullanıcı kabulü akışını göster.
4. Sürüme not: CHANGELOG 5.1.1 maddeleri kısaltılarak kullanılabilir.
5. 20 cihazlık dahili iz yerine kapalı izde birkaç günlük duman testi yeterli.

---

*Tüm maddeler yeşile çizilmeden üretime geçme. — C-Stone Labs*

---

## v5.1.3 kapak doğrulaması (6 Eylül 2026)

1. Dün kapak göstermeyen şarkıları aç → artık **orijinal kapaklar** görünmeli
2. Ayarlar → yedek görsel (taş/nota) değişimi hâlâ çalışmalı
3. Dosya bilgileri → yalnızca başlık düzenle → kaydet → kapak (varsa) görünürlüğü
   korunmalı, eskiden "yok" denilen şarkıda kapak belirebilir
4. Bildirim + kilit ekranı kapağı: şarkı değişince doğru kapak (önbellek
   birleştirildi; ilk açılışta bir kez çıkarır, sonra hızlı)
5. `flutter test` → 3 eski + 4 yeni test = 7 geçmeli

## v5.1.3 M4A doğrulaması (6 Eylül)

1. Music klasöründeki .m4a dosyaları: sanatçı/albüm/kapak dolmalı
   (ilk açılışta backfill 50'lik partilerle dolar — birkaç saniye)
2. M4A çal, bildirimde kapak ve isim doğru mu
3. M4A'da Dosya bilgileri → düzenle → "yalnızca uygulamada" uyarısı +
   kütüphanede güncellenme (dosyaya dokunulmaz)
4. MP3 etiket yazma hâlâ çalışmalı (regresyon yok)

## v5.1.3 Android Auto kuyruk doğrulaması (6 Eylül)

1. Arabada/Auto'da Şarkılar → bir şarkıya bas → direksiyondan İLERİ:
   gerçekten SONRAKİ şarkı çalmalı (başına sarma YOK)
2. GERİ: önceki şarkuya dönmeli
3. Şarkıyı sonuna kadar bekle → sonraki şarkıya geçmeli (tekrar etmemeli)
4. Klasörlerden bir klasöre gir → şarkı bas → kuyruk o klasörün şarkıları
   olmalı (kuyruk ekranından doğrula)
5. Telefonda (Auto'suz) ileri/geri/şarkı sonu davranışı değişmemeli

## v5.1.3 Rapor re-freeze doğrulaması (10 Eyl)

1. Bir şarkıyı TAM çal (40+ sn) → uygulamayı kapat → tarihi Pazartesi'ye al
   → rapor: çalma sayısı >0, şarkı "En çok dinlenenler"de olmalı
2. Aynı hafta içindeyken tekrar dinle → tekrar Pazartesi'ye al → rapor
   YENİ çalmaları da içermeli (önceki sürümde eski rapor takılı kalıyordu)
3. Normal akış: hafta içinde dinle, ertesi Pazartesi doğal gelince rapor
   doğru olmalı (değişiklik normal hayatı bozmamalı)

## v5.1.3 Çoklu seçim + arama kuyruğu + küme birleşimi (10 Eyl)

1. Şarkılar: bir şarkıya BASILI TUT → seçim modu (üstte sayı, Tümünü seç,
   kapat); dokunarak başka şarkılar ekle; seçili kartta turuncu onay
2. Aynı şeyi Favoriler, bir çalma listesinin içi, klasör içi ve akıllı
   listede dene; ARAMA yapıp ("montagem" gibi) çıkan sonuçları da seç
3. Alt çubuk: Favorilere ekle → favoriler sekmesinde görünsün
4. Alt çubuk: Listeye ekle → var olan listeye VE "yeni liste kur"a ekle
5. Alt çubuk: Paylaş → sistem paylaşım sayfası çoklu dosya ile açılsın
6. Alt çubuk: Sil → "Sadece Uygulamadan" ve "Uygulama+Telefondan";
   TEK onay penceresi "n şarkı silinsin mi?" gelsin
7. Arama: Türkü listesinde bir şarkı ara → çal → İLERİ: arama sonucu
   değil, LİSTEDEN sıradaki şarkı çalmalı
8. Küme birleşimi: kütüphanede mevcut bir şarkıyı + ile yeniden eklemeye
   çalış → kopya/numaralı kayıt OLMAMALI
9. Aynı klasörü Klasörler sekmesinden yeniden ekle → şarkılar ikiye
   katlanmamalı
10. Uzun süre kullanım: seçim modundayken mini oynatıcı ve çalma akışı
    bozulmamalı (seçim yalnızca görünürlüğü değiştirir)

## v5.1.3 Seçim UX ikinci tur (10 Eyl)

1. Sarı/kırmızı: ⋮ menü VE seçim çubuğunda "Sadece Uygulamadan Sil" sarı,
   "Uygulamadan ve Telefondan Sil" kırmızı olmalı
2. Favoriler sekmesi: basılı tut → ilk aksiyon "Çıkar" (yıldız değil çıkar
   ikonu); ⋮'de yıldız simgesi
3. Liste detayı: seçim çubuğunda "Listeden Çıkar"; "Liste" yok
4. "Liste" aksiyonu: ⋮ menüsündeki "Çalma Listesine Ekle" diyaloğunun
   AYNISI açılmalı (Yeni Liste Oluştur + onay ikonlu liste)
5. Tümünü seç: Şarkılar, Favoriler, liste detayı, klasör içi, akıllı liste,
   Listeler (listeler), Klasörler (klasörler) — HER yerde
6. Aratıp seç: birkaç şarkı seç → ara → başka seç → aramayı temizle →
   SEÇİM KORUNMALI; "Tümünü seç" arama sonuçlarını mevcut seçime EKLER
7. Boş alana dokun → seçim modu kapansın; geri tuşu → önce seçim kapansın,
   sonra uygulama ARKA PLANA geçsin (kapanmasın!)
8. Klasöre gir + akıllı listeye gir → mini oynatıcı görünmeli (çalarken)
9. Uzun adlı şarkı çal → listede/mini/Şimdi Çalıyor'da ad KAYMALI
10. Kütüphanedeki bir şarkıyı "Sadece Uygulamadan Sil" → + ile AYNI dosyayı
    seç → KENDİ klasöründe görünmeli (sayısal klasör YOK)
11. Mini ✕ → uygulamayı kapat → yeniden aç → son çalınan DOĞRU şarkı olmalı
12. Listeler sekmesi: listeye basılı tut → çoklu liste sil; Klasörler:
    klasöre basılı tut → çoklu klasör kaldır (tek onay)

## v5.1.3 Üçüncü tur (10 Eyl)

1. Klasör içine VE akıllı listeye gir → ekran DÜZGÜN açılmalı (beyaz yok),
   alt sekmeler görünüyor olmalı, mini oynatıcı çalarken orada olmalı
2. Herhangi bir listede şarkıya basılı tut → mini oynatıcı kayarak İNSİN,
   seçim çubuğu tam genişlik ve düz görünsün; seçimi bitir → mini dönsün
3. Klasörler sekmesi: klasöre basılı tut → anında seçilmeli (başka sekmeye
   geçmeden!), "n klasör seçildi" çubuğu canlı, Vazgeç anında çalışmalı;
   Listeler sekmesinde listeler için aynısı
4. Favorilerdeki şarkıyı (herhangi bir ekranda) seç → ilk aksiyon "Çıkar"
5. ⋮ menüsünde "Sadece Uygulamadan Sil" SARİ ikon; telefondan silme kırmızı
6. Rapor ekranı → zemin tema rengiyle uyumlu (koyulaşma yok), kartlar/çubuklar
   yine kendi renginde
7. Ayarlar → uygulama içi sürüm "5.1.3" yazmalı
8. Geri tuşu: klasör içinden → klasörlere; sekmelerde → Şarkılar'a;
   Şarkılar'dayken → çıkış

## v5.1.3 Dördüncü tur (10 Eyl)

1. + ile AYNI şarkıyı 3 kez eklemeye çalış → Şarkılar'da TEK kayıt;
   klasörde tek; birini seçince yalnız o seçilir (klon yok)
2. Uzun isimli şarkı: çalarken isim kayar, çalmıyorken sade durur
3. Aratıp seç: birkaç seç → ara → sonuca YENİ uzun bas → seçime EKLENMELİ
   (öncekiler kaybolmaz); aramayı temizle → seçim durur
4. Favoriler dışında favori şarkı seç → "Favorilerden Çıkar"; Favoriler
   sekmesinde → "Çıkar"
5. Seçim modundayken boş alana dokun (Favoriler, Listeler, Klasörler,
   klasör içi, akıllı liste, Şarkılar) → seçim kapanır
6. Seçim modu açıkken ⋮'ye bas → seçim kapanır, menü güncel açılır;
   menü açıkken mini oynatıcı GİZLİ; kapatınca geri gelir
7. Tema değiştir → Klasörler sekmesi (kartlar + arama çubuğu) ve klasör
   içi ANINDA yeni temada (çık-gir gerekmez)

## v5.1.3 Beşinci tur (10 Eyl)

1. Uzun isimli şarkı çal → ad SÜREKLİ kayar (durma/ışınlanma yok, soldan
   çıkıp sağdan girer)
2. Favori şarkıyı Favoriler DIŞINDA bir listede seç → "Favorilerden Çıkar"
   etiketi taşmadan, düzgün görünür
3. + ile tek dosya (zaten varsa) → "Dosya zaten listede"; çoklu hepsi
   varsa → "Dosyalar zaten listede"; karışıksa → "k dosya zaten
   listedeydi. n şarkı eklendi."; hepsi yeniyse → "n şarkı eklendi"

## v5.1.3 Altıncı tur (10 Eyl)

1. Herhangi bir bildirim cümlesi (şarkı eklendi, favorilere eklendi,
   silindi, hata…) → yüzen yuvarlak kutu, solda ikon, vurgu rengi doğru
   (ekleme turuncu / silme-hata kırmızı / kaydetme onay)
2. + ile ekleme mesajları yeni tasarımla ve doğru cümlelerle gelmeli

## v5.1.3 Yedinci tur (10 Eyl)

1. Bildirim: yumuşak animasyonla gelir/gider (TAK yok); parmağını
   üstünde tut → süre dolsa da gitmez; bırak → ~0,7 sn sonra gider;
   tekrar tut → yine 0,7 sn kuralı
2. Seçim modu açıkken bildirim çıkarsa kutu seçim çubuğunun ÜSTÜNDE
   durur (çubuk görünür ve basılabilir kalır)
3. Bildirim çıkınca mini oynatıcı YUKARI kayar (kaybolmaz), kapanınca
   geri iner
4. Favori olmayan A + favori B'yi seç → Favori → "Bir şarkı favorilere
   eklendi. Diğeri zaten vardı." + etiket "Favorilerden Çıkar" olur
5. Hepsi favoriyken tekrar → "Seçilen şarkılar zaten favorilerde."
6. Tek şarkı ⋮ → Çalma Listesine Ekle → içinde olduğu listeye bas →
   "Bu şarkı zaten 'X' listesinde." VE şarkı listeden SİLİNMEMELİ
   (eski davranış sessizce siliyordu — kontrol et!)
7. Çoklu seçim → Liste → kısmen dolu liste → '"X" listesine 2 şarkı
   eklendi. Diğeri zaten listedeydi.'

## v5.1.3 Sekizinci tur — A+B (11 Eyl)

1. Herhangi bir bildirim → yazıda sarı altı çizgi YOK
2. Kutuyu parmakla aşağı çek → parmağı izler; az çekip bırakınca geri
   döner; yeterince itersen kapanır
3. Parmak kutunun üstündeyken süre durur; bırakınca ~0,7 sn sonra gider
4. ⋮ menüsü açıkken bildirim oluşursa → menü kapanınca görünür
5. Mini oynatıcı YOKKEN (şarkı seçili değil) bildirim → sekmelerin
   üzerinde, bindirme yok; seçim modunda → seçim çubuğunun üstünde
6. Mini oynatıcı + kutu aynı anda → mini kutunun hemen üstünde, temas
   yok; kutu kapanınca mini yerine döner
7. ⋮ → Favorilere Ekle/Çıkar → kutu gelir; Sadece Uygulamadan Sil →
   "Şarkı uygulamadan kaldırıldı."; mini çubuktaki ★ → kutu gelir
8. Ayarlar → ekolayzır ve Dosya bilgileri ekranı → teknik terim yok
9. Silme/hata akışlarında İngilizce istisna/dosya yolu içeren mesaj YOK
10. Genel: geçişler artık aynı tempoda (farklı hızda "zıplayan" animasyon
    yok); kart köşeleri tutarlı

## v5.1.3 Dokuzuncu tur (11 Eyl)

1. Şarkı çalarken herhangi bir ⋮/seçim eyleminden kutu gelince mini
   oynatıcı UÇMAMALI — sadece kutunun üstüne çıkıp yer açmalı, kutu
   kapanınca eski yerine dönmeli
2. Listeler/Favoriler/Klasörler/Akıllı sekmelerinde de aynısı (kök
   katman — hepsi aynı çalışmalı)
3. Kutuya hızlı dokunuş → hiçbir şey olmamalı (kutu kalmaya devam);
   0,5 sn+ BASILI tutup bırak → ~0,7 sn sonra kapanmalı; aşağı çek →
   kapanmalı
4. Seçim çubuğu aksiyonları: Şarkılar/klasör içi/akıllı içi → SADECE
   Paylaş+Sil; liste detayı → Listeden Çıkar+Paylaş+Sil; Favoriler →
   Çıkar+Paylaş+Sil (Favori/Liste EKLEME düğmesi hiçbirinde olmamalı)
5. Klasör/liste seçildi çubuğu → yüzen kapsül, sekmelerle arasında boşluk

## v5.1.3 Onuncu tur (11 Eyl)

1. Kutu gelince mini SADECE kutunun hemen üstüne süzülmeli (uçmamalı);
   kutu gidince mini eski yerine dönmeli — her sekmede ve şarkı yokken
2. Kutu: hızlı dokunuş → bir şey olmaz; basılı tut → süre durur, bırak →
   ~0,7 sn; aşağı it → kapanır
3. Seçim açıkken alttan sekme değiştir → seçim kapansın + mini geri gelsin
4. Başlıktaki "n şarkı/klasör/liste seçildi" yazısına dokun → seçim kapansın;
   klasör seçince başlıkta sayı görünsün
5. Klasör çubuğunda Paylaş → seçili klasörlerin şarkıları çoklu paylaşılır;
   liste çubuğunda Paylaş aynı; akıllı listeye uzun bas → Listeyi Paylaş
6. Dosya bilgileri: yeni düzen (büyük kapak + rozet, çipler, etiket kartı);
   kapak seç→kırp→uygula akışı ve kaydetme eskisi gibi çalışmalı

## v5.1.3 On birinci tur (11 Eyl)

1. Şarkı çalarken herhangi bir eylemden kutu gelince mini GİZLENMELİ
   (uçmamalı!); kutu kapanınca mini yerine dönmeli — her sekmede
2. Kutu: parmağınla aşağı sürükle → canlı izler; yukarı çek → geri gelir;
   ~yarısından fazla it → parmak kalkmadan kapanır; hızlı savurma →
   kapanır; az it + bırak → yaylanıp yerine döner
3. Klasör paylaşı (1 klasör) → WhatsApp'ta TEK "Music.zip" dosyası
   gelmeli (ayrı ses kayıtları DEĞİL); içinde şarkılar düzgün adlarla
4. Liste paylaşı → "ListeAdı.zip"; çoklu seçim paylaşı → "n şarkı.zip";
   TEK şarkı paylaşı → düz dosya (klasörsüz)
5. Boş akıllı listeye uzun bas → "Bu liste boş" bilgisi; boş klasör
   paylaşma → bilgi
6. M4A dosyasında etiket/kapak değiştir → "Dosyaya yaz" → WhatsApp/dosya
   yöneticisinde etiketler GÜNCEL olmalı; başarısız olursa dosya eski
   hâlini korumalı
7. Kapağı kaldır → buton "Geri al" olur → bas → özgün kapak döner
8. OPUS/OGA/AMR dosyası + ile eklenip çalınabilmeli

## v5.1.3 On ikinci tur (11 Eyl)

1. Ayarlar: tema kartlarına dokun → anında değişir + turuncu seçim vurgusu;
   kapak kartları aynı; pil izni, klasör çipleri, "Şimdi tara", ekolayzır,
   hakkında/gizlilik diyalogları — hepsi eskisi gibi çalışmalı
2. Rapor: başlıklar yumuşak ("Geçen Hafta", "En Çok Dinlenenler")
3. Favoriler/Listeler boş ekran: yumuşak rozetli ikon

## v5.1.3 On üçüncü tur (11 Eyl)

1. Klasör/liste paylaşı → "'X.zip' hazırlanıyor…" penceresi döner göstergeyle
   gelmeli; bu sırada başka yere dokunmak/genie basmak İŞE YARAMAMALI;
   paylaşım ekranı hazırlanınca açılmalı
2. Liste ⋮ → Yeniden Adlandır → yeni ad → kaydet → listede ad değişmiş
   olmalı + kutu "Liste yeniden adlandırıldı." demeli; Sil eskisi gibi
3. Klasör ⋮ → Yeniden Adlandır → telefondaki DOSYA YÖNETİCİSİNDE de klasörün
   adı değişmiş olmalı; Klasörler sekmesi ve klasör içi şarkılar yeni adla
   çalışmalı; çalma/listeler bozulmamalı
4. İzin verilmezse (bazı Android'ler): kırmızı bilgilendirme gelmeli,
   hiçbir şey kaybolmamalı

## v5.1.3 On dördüncü tur (11 Eyl)

1. Çoklu paylaş → seçim sheet'i: "Ayrı Ses Dosyaları" / "Tek ZIP"; ayrı
   seçilirse WhatsApp'ta her şarkı ayrı gider (bilinçli seçim); ZIP
   seçilirse hazırlanıyor penceresi + tek zip
2. Çoklu seç → Uygulamadan ve Telefondan Sil → TEK sistem onayı (her
   şarkı için ayrı diyalog OLMAMALI — Android 11+)
3. Klasör içinde şarkı sil → anında listeden düşmeli; tümünü sil →
   "izlemeden çıkarıldı" + otomatik listeye dönüş
4. Klasörler + → seçim sheet'i; "Müzik Dosyalarından" ile 2 farklı
   klasörden şarkılar seç → 2 klasör de eklenmeli; Ayarlar → Kütüphane
   → Klasör Ekle aynı
5. Ayarlar: her bölüm başlığında (i) → açıklama diyaloğu; klasör çipine
   dokun → o klasör taranır; Tümünü Tara çalışır
6. Klasör ⋮ → Bu Klasörü Tara; AppBar'da Tümünü Tara ikonu
7. Favoriler → sağ üst paylaş → "Favoriler.zip" ya da ayrı dosyalar
8. Listeye şarkı ekle → Kaydet → dönünce renk sıçraması YOK

## v5.1.3 On beşinci tur (11 Eyl)

1. Dosya bilgileri → Dosyaya yaz (MP3 VE M4A, klasörden eklenmiş dosyada):
   izin diyalogu gelirse ver → "Dosyaya yazıldı." olmalı; başarısızsa
   mesaj sakin: "Dosyaya yazılamadı. Tekrar dene." (korkutucu ifade yok)
2. Bildirim çubuğu: ★ solda, ✕ sağda (sistem bildirimindeki düzen)
3. Butonlara basınca minicik küçülme animasyonu; sekmeler arası geçişte
   kısa soluklanma (abartısız)
4. Klasörler + → seçim sheet'i çalışmalı (08:19'daki derleme hatası gitti)

## v5.1.3 On altıncı tur (11 Eyl)

1. Kuyruğun SON şarkısını çal → bildirimde ileri ok HÂLÂ GÖRÜNÜR;
   bas → kuyruğun İLK şarkısına sarar; yıldız ve çarpı yerinde durur
2. Mini oynatıcı ve Şimdi Çalıyor'daki ileri de sonda başa sarmalı
3. Uygulama içi bildirim çubuğu: ✕ solda, ★ ve çal/duraklat sağda
   (özgün düzen)

## v5.1.3 On yedinci tur (11 Eyl)

1. Klasörler + → (izin yoksa diyalog: İzin Ver → ayarlar) → izni ver →
   geri gel, tekrar + → UYGULAMA İÇİ tarayıcı: klasörlere dokunarak in,
   "Bu Klasörü Kullan" / işaretle çoklu ekle → özet kutusu
2. İzin verdikten sonra: Dosya bilgileri → Dosyaya yaz → izin diyaloğu
   YOK, direkt "Dosyaya yazıldı." olmalı (MP3 + M4A)
3. Klasör ⋮ → Yeniden Adlandır → izinliyken TELEFONDA da adı değişmeli
4. Tümünü Tara (AppBar + Ayarlar) → "n yeni şarkı eklendi." ya da
   "Kütüphane güncel." kutusu gelmeli
5. Favoriler sekmesi sağ üst paylaş → sorar (ayrı/zip); LİSTELER
   sekmesinde bu düğme OLMAMALI
6. Paylaşım sheet'inde ✓ yok; her iki biçimde de dönen "hazırlanıyor"
7. Tüm sheet'ler/menüler sistem nav çubuğunun üstünde
8. Seçim modunda başlığın yanındaki boşluğa dokun → seçim kapansın
9. Ayarlar başlığında logo; liste ekle → Kaydet → dönünce renk akışı
   kesintisiz; akıllı liste kartları rozetli

## v5.1.3 On sekizinci tur (11 Eyl)

1. Klasör seçici (izin verdikten sonra Klasörler + ya da Şarkılar sağ
   üst klasör simgesi): SADECE müzik içeren klasörler; "0" yazan düğme
   YOK; kutucukla işaretle → altta "Klasörü Ekle" / "4 Klasörü Ekle";
   işaretler klasör gezerken KORUNMALI
2. Seçicideyken geri (nav çubuğu/ok) → BİR ÜST klasör; en başta
   (Müzik Klasörleri) geri → ekran kapanır
3. İzin akışı (Veriyi sil sonrası): + → İzin Ver → ayarlar AÇILMALI
   (üç kademeli deneme) → izni ver → dön → "İzin verildi" kutusu ve
   seçicinin doğrudan açılması
4. İzin AÇIKKEN Dosyaya yaz başarısız olursa "izin gerekiyor"
   DEMEMELİ (dürüst hata kutusu); izin KAPALIYKEN diyalog → İzin Ver
   → ayarlar açılır, dönünce sonuç söylenir
5. Dosya bilgilerinde metin kutusuna dokun → imleç; BOŞ yere dokun →
   klavye kapanır, imleç kalkar
6. Listede 3 şarkı varken: ⋮ → Bu Listeden Çıkar VE çoklu seçim →
   Sil (her iki mod) → sayaç HEMEN 2 olmalı; favoriler de öyle
7. Şarkı Ekle ekranı: kapaklı satırlar, yuvarlak işaretler, altta
   "n şarkı seçili" + Kaydet; kaydet dönünce sayaç güncel
8. Hızlı tur: paylaşım akışları, hazırlanıyor pencereleri, SafeArea
   (değişmedi — kırılmadıklarını gör)

## v5.1.3 On dokuzuncu tur (11 Eyl)

1. Klasör simgesi → seçici: klasöre dokun → içi AÇILIR, şarkılar kapak
   ve adlarıyla görünür; "altında müzik klasörü yok" mesajı YOK
2. Şarkıya dokun → seçim başlar; klasörü BASILI TUT → klasör seçimi;
   boşluğa dokun / ✕ → seçimden çık; Tümünü seç → görünür her şey
3. Alt düğme etiketleri: Klasörü Ekle / 4 Klasörü Ekle / Şarkıyı Ekle /
   3 Şarkı Ekle / "2 Klasör + 5 Şarkı Ekle"
4. Tek tek ekleme: izlenmeyen klasörden 2 şarkı seç → "2 şarkı tek tek
   eklendi." → Şarkılar sekmesinde çal
5. Özetler: izlenen klasörü tekrar seç → "Bu klasör zaten izleniyor.";
   karışık seçim → "… Diğer ikisi zaten izleniyordu."; klasör + tek tek
   eklenmiş şarkılar → "Klasör eklendi, N şarkı alındı. M tanesi zaten
   kütüphanedeydi."
6. Şarkılar sekmesinde + YOK; sağ üstte rapor + klasör simgesi
7. Dosyaya yaz (mp3 + m4a): izinliyken SİSTEM DİYALOGU ÇIKMADAN yazmalı;
   küçülen dosyada da başarı; gerçek hata → "Dosyaya yazılamadı.
   Tekrar dene."
8. Hızlı tur: geri = üst klasör, sayaç budama, imleç kalkması, SafeArea

## v5.1.3 Yirminci tur (11 Eyl)

1. Şarkılar sekmesi: klasör simgesi RAPORUN SOLUNDA; boş kütüphanede
   "Henüz şarkı yok…" ortalı ve düzgün; + yok (önceki turdan)
2. Tema animasyonu: SOĞUK AÇILIŞTA akmalı (uygulamayı arka plana
   alıp dönmeye gerek yok); Şimdi Çalıyor'da uzun süre donmamalı
3. Tema sıçraması: klasör seçiciden klasörler sekmesine dönüş,
   liste detayından listelere dönüş, şarkı ekleme ekranı girişi/çıkışı
   — hiçbirinde renk atlaması OLMAMALI
4. Klasör seçici: klasör geçişinde hafif kayma+solma; son şarkı/
   klasör satırı nav çubuğunun ÜSTÜNDE; ipucu satırı listenin
   başında (seçim modunda yok)
5. Seçim: tek şarkıyı seç → geri al → seçim modu KENDİLİĞİNDEN
   biter (klasörde de öyle); GERİ tuşu seçim modunda seçimi bırak,
   normalde üst klasör, en başta ekran kapanır
6. Sekme değişince seçim modu kapanır (ana ekranda zaten vardı —
   kırılmadığını gör)
7. Özetler: izlenen klasörü tekrar ekle → yeniden taranır: '"Music"
   zaten izleniyordu — 5 şarkı geri eklendi.' / yeni klasör →
   '"Music" eklendi, N şarkı alındı.'
8. Listeler ⋮: Şarkı Ekle (ekrana girip ekleyebilme) + Paylaş
   (ayrı/zip sorar) çalışmalı

## v5.1.3 Yirmi birinci tur (11 Eyl)

1. TEMA: gündüz + otomatik temada klasör simgesine gir → artık siyah
   KARIŞMASI yok; liste detayı / şarkı ekleme / akıllı detay / klasör
   şarkıları / dosya bilgileri / rapor giriş-çıkışlarında renk akışı
   kesintisiz
2. PAYLAŞIM: 10+ şarkı seç → ZIP → "hazırlanıyor" DÖNER ve akar
   (donmaz), iş bitince paylaşım sayfası açılır; Ayrı dosyalar da öyle
3. Boş listenin ⋮ → Paylaş → "Paylaşılacak şarkı yok." kutusu
4. Klasörler ⋮ → Paylaş; Akıllı liste ⋮ → Paylaş; akıllı liste BASILI
   TUT → seçim modu (sadece Paylaş çubuğu), boşluğa dokun/✕ → çıkış
5. Ayarlar → Kütüphane: "Son tarama" YOK; "Klasör Seçici" segmenti:
   Sistem'e al → + → SİSTEM seçici açılır; Uygulama İçi'ne al → bizim
   seçici
6. Klasör seçicide ipucu satırı seçim modunda da durur

## v5.1.3 Yirmi ikinci tur (11 Eyl)

1. Klasör içine gir → şarkı ⋮ → Sadece Uygulamadan Sil → ŞARKI ANINDA
   listeden düşmeli (çık-gir YOK); seçim çubuğuyla toplu silmede de
2. Dosya bilgileri → Dosyaya yaz (mp3 + m4a) → izinliyken yazmalı
   (doğrudan yazma); başka uygulamada/çalarken dene
3. İç ekranlardan (liste detayı, şarkı ekleme, akıllı detay, klasör
   içi, rapor) GERİ dönüş — tema sıçraması/çift görüntü YOK (geçişler
   yumuşak solma)
4. Ayarlar → Klasör Seçici bölümü: (i) açıklaması; Cobblestone Seçici /
   Sistemin kendi seçicisi kartları — seçim kalıcı, + buna uyar

## v5.1.3 Yirmi üçüncü tur (12 Eyl)

1. Dosya bilgileri → Dosyaya yaz: mp3 VE m4a — izinliyken yazmalı;
   yazamazsa mesaj SEBEP söyler (m4a biçimi / izin / dosya yok);
   hata_gunlugu.txt'ye "dosyaya_yaz" kaydı düşer
2. Ayarlar → Kütüphane: klasör KARTLARI (ad + şarkı sayısı), satıra
   dokun = tarama; ⟳ = tarama; 🗑 = onay → klasör + şarkıları
   uygulamadan çıkar (telefon dosyaları durur), sayaçlar anında düşer
3. Klasörler sekmesi + Ayarlar tutarlılığı: kaldırılan klasör her
   ikisinde de yok olmalı

## v5.1.3 Yirmi dördüncü tur (12 Eyl)

1. Klasör seçici: klasöre DOKUN → seçim başlar (şarkı gibi); BASILI TUT
   → klasöre GİR; ipucu satırı yeni düzeni anlatıyor
2. Dosyaya yaz (mp3 + m4a): izinliyken yazmalı. YAZAMAZSA kutudaki
   parantezli NEDENİ aynen bildir (örn. "üzerine yazma:
   FileSystemException… errno = 30") — teşhis için şart
3. Yazarken şarkı ÇALARKEN de dene (strateji B/rename bunun için)

## v5.1.3 Yirmi beşinci tur (12 Eyl)

1. m4a şarkı → Dosya bilgileri → başlık/sanatçı değiştir → Dosyaya
   yaz → "Dosyaya yazıldı." OLMALI (©nam atomu düzeltildi — asıl neden)
2. m4a → kapak ekle/değiştir → Dosyaya yaz (covr atomu aynı yoldan)
3. mp3 → Dosyaya yaz (etkilenmemişti — yine çalışıyor olmalı)
4. Türkçe karakterli başlık/sanatçı her iki biçimde
5. Klasör seçici: dokun=seç, basılı tut=gir (önceki tur — onaylandı)
