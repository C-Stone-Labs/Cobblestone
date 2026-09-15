# Cobblestone — Play Store yayın notları

**Paket:** `com.cobblestone.cobblestone`  
**Sürüm:** 5.1.3 (versionCode 55)  
**Min SDK:** 24 (Android 7) · **Hedef:** Flutter `targetSdk` (API 36 olmalı — bkz. aşağıda "Kapalı test güncelleme")

## İmza

Play Store **kendi keystore'unla** imzalı AAB ister. Bu ortamda üretilen APK
debug anahtarıyla imzalıdır; 4.0'ın üzerine kurulmaz.

Kendi bilgisayarında:

```
# android/key.properties
storePassword=...
keyPassword=...
keyAlias=cobblestone
storeFile=/tam/yol/cobblestone-key.jks
```

```
cd cobblestone
flutter pub get
flutter build appbundle --release
```

Çıktı: `build/app/outputs/bundle/release/app-release.aab`

## Kapalı test güncelleme (v5.1.1 için)

**Testi SİLME.** Aynı kapalı test izine yeni bir sürüm yükle:

1. Play Console → Kapalı test → iz → "Yeni sürüm oluştur"
2. Yeni AAB (versionCode **52**, hedef API **36** — 31 Ağu 2026'dan beri
   güncellemeler için zorunlu; güncel stable Flutter ile derle).
3. Testler ve süreklilik korunur. Kişisel hesaplarda üretime geçiş için
   en az 12 testçi 14 gün aralıksız seçili olmalı — testi silmek bu
   sayacı sıfırlar.
4. İzin bildirimi videosu yanlışsa: App content → izin bildirimi sayfasını
   düzenleyip doğru video bağlantısıyla yeniden gönder. Yeni sürüm
   yüklemek bildirimleri silmez; izin seti aynı kaldığı sürece onaylı
   bildirim geçerli kalır.
5. `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` videosunda şunu göster:
   Ayarlar → "Arka planda kesilmesin" düğmesi → sistem diyaloğu → kabul.
   (İzin yalnızca kullanıcı hareketiyle isteniyor — video bunu kanıtlamalı.)

## Mağaza metni (TR)

**Kısa açıklama (80 karakter):**  
Reklamsız, çevrimdışı MP3 çalar. Hesap yok, internet yok — sadece müziğin.

**Uzun açıklama:**  
Cobblestone, telefonundaki müziği gürültüsüz dinlemen için yapılmış yerel bir çalar.

• İnternet yok, hesap yok, reklam yok  
• Klasör seç, şarkıların otomatik taransın  
• Çalma listeleri ve favoriler  
• 10 bant ekolayzer + bas + sanallaştırıcı  
• Kilit ekranı ve bildirim kontrolleri  
• Gece / gündüz atmosfer teması  
• Haftalık dinleme raporu  

Müzik dosyaların telefondan dışarı çıkmaz.

## Veri güvenliği formu

- Veri toplanır mı? **Hayır** (uygulama ağı kullanmaz)
- Dosyalar ve ses: yalnızca cihazda, kullanıcının seçtiği klasör
- Şifre / konum / kişi: yok
- Reklam kimliği: yok
- Çocuklara yönelik mi? Hayır

## İzinler (Play Console açıklaması)

| İzin | Neden |
|---|---|
| READ_MEDIA_AUDIO | Kullanıcının seçtiği klasördeki ses dosyalarını okumak |
| FOREGROUND_SERVICE_MEDIA_PLAYBACK | Ekran kapalıyken müzik çalmak |
| FOREGROUND_SERVICE_DATA_SYNC | Büyük müzik klasörünü tararken sürecin öldürülmemesi |
| POST_NOTIFICATIONS | Medya bildirimi (play/pause) |
| REQUEST_IGNORE_BATTERY_OPTIMIZATIONS | İsteğe bağlı; bazı üreticiler arka plan çalmayı kesmesin |
| RECEIVE_BOOT_COMPLETED | Haftalık rapor alarmını yeniden kurmak |
| MODIFY_AUDIO_SETTINGS | Ekolayzer / sanallaştırıcı |

## Ekran görüntüleri

Telefon: 16:9 veya 9:16, en az 2 adet. Önerilen sahneler: Şarkılar listesi,
Şimdi Çalıyor, Listeler/Favoriler, Ayarlar (ekolayzer).

## İçerik derecelendirme

Müzik & Ses. Kullanıcı kendi dosyalarını çalar; uygulama içerik barındırmaz.

## Yayın öncesi kontrol

- [ ] `key.properties` + `.jks` ile AAB üretildi
- [ ] Paket adı Play Console ile aynı
- [ ] Sürüm kodu bir önceki yüklemeden büyük
- [ ] Gizlilik politikası URL'si (Play, "veri toplanmıyor" uygulamalarında
      bile bazen ister — kısa bir statik sayfa yeter)
- [ ] Hedef kitle 18+ veya 13+ seçildi
- [ ] 20 cihazlık dahili test izi
