# Cobblestone

Reklamsız, çevrimdışı, hesapsız yerel MP3 çalar.

**Sürüm:** 5.1.3 (versionCode 55)  
**Paket:** `com.cobblestone.cobblestone`  
**Geliştirici:** C-Stone Labs

Flutter arayüz + Android Media3 (bildirim, kilit ekranı, arka plan, Android Auto).

---

## Ne yapar

- Şarkılar, Klasörler, Listeler, Favoriler
- Akıllı listeler (4. sekme): En çok / Az / Hiç — Pazartesi raporuna kilitli
- Mini oynatıcı (Ayarlar dışında)
- Android Auto (medya tarayıcı)
- Samsung medya paneli / “son şarkıyı çal”
- Sonra çal / sıraya ekle
- Dosya bilgileri: kapak kırpma, etiketleri dosyaya yaz
- Albüm kapağı (ID3 veya kullanıcı); yoksa ayardan taş / nota
- 10 bant ekolayzer, bas, sanallaştırıcı
- Hız (0.5×–2.0×), karıştır, tekrarla
- Haftalık dinleme raporu (Pazartesi kilit)
- Klasör tarama veya dosya seçiciyle ekleme

İnternet yok, hesap yok, reklam yok. Müzik dosyaları telefondan dışarı çıkmaz.

---

## Derleme

Gerekli: Flutter SDK, Android SDK.

```bash
cd cobblestone
flutter pub get
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`

Play AAB ve imza: `PLAY_STORE.md`.

`android/key.properties` ve `*.jks` bu zip’te yoktur; kendi imzanı kullan.

---

## GitHub

Bu klasör depo köküdür.

```bash
cd cobblestone
git init
git add .
git commit -m "Cobblestone 5.1.0"
git branch -M main
git remote add origin git@github.com:KULLANICI/DEPO.git
git push -u origin main
```

**Yükleme:** `android/key.properties`, `*.jks`, `*.keystore`, `android/local.properties`, `build/`, `.dart_tool/`  
(`.gitignore` bunları dışlar.)

---

## Klasörler

```
lib/           Flutter (ekranlar, servisler, widget’lar)
android/       Media3 servisi, bildirim, Auto, EQ
assets/icon/   Logo ve yedek kapak
test/          ID3 birim testi
PLAY_STORE.md  Mağaza / imza notları
CHANGELOG.md   Sürüm notları
```

Native:

- `PlaybackService.kt` — çalma, bildirim, Android Auto kütüphanesi
- `MainActivity.kt` — Flutter ↔ Media3
- `BrowseTree.kt` — Auto tarama ağacı
- `EqEngine.kt` — ekolayzer
- `FavoritesStore.kt` — bildirim yıldızı

---

## Lisans

Kaynak sana ait. İstediğin gibi kopyala, GitHub’a at.
