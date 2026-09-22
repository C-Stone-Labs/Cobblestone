# 🎵 Cobblestone

**Cobblestone**, Flutter ve Kotlin kullanılarak geliştirilmiş; modern, yüksek performanslı ve çevrimdışı (offline) bir Android müzik çalar uygulamasıdır.

Şık kullanıcı arayüzü, gelişmiş ekolayzır motoru, Android Auto desteği ve akıllı müzik kütüphanesi yönetimi ile kusursuz bir ses deneyimi sunar.

---

## ✨ Öne Çıkan Özellikler

- 🚗 **Android Auto Desteği:** Araç içi ekranlarla tam entegrasyon. Şarkı listelerinize ve medya kontrollerine sürüş esnasında güvenle erişin.
- 🎛️ **Özel Biquad Ekolayzır (EQ):** Kotlin tarafında yerel (native) olarak işlenen gelişmiş ses ekolayzırı ve ses efektleri.
- 📁 **Gelişmiş Klasör Yönetimi:** Müzik kütüphanenizi klasör yapısına göre tarayın, özel klasörler seçin ve klasör değişikliklerini canlı izleyin.
- 🧠 **Akıllı Çalma Listeleri (Smart Playlists):** En çok dinlenenler, son eklenenler ve favorilere göre otomatik oluşturulan dinamik listeler.
- 🎨 **Kapak Resmi Düzenleme & Kırpma:** Şarkı kapak görsellerini özelleştirin ve uygulama içinde dilediğiniz gibi kırpın.
- 📊 **Dinleme İstatistikleri:** En çok dinlediğiniz şarkıları ve müzik alışkanlıklarınızı analiz eden istatistik servisi.
- 🌊 **Dinamik Ritim ve Animasyonlar:** Şarkı ritmine duyarlı görselleştiriciler ve özelleştirilebilir animasyon seviyeleri.
- ⚡ **Yüksek Performans & Akıcı Arayüz:** Akıllı önbellekleme, hızlı ID3 etiket okuma ve kasma yapmayan akıcı sayfa geçişleri.
- **apk olarak kurarsanız android auto ayarlarından geliştirici modunu etkinleştirip bilinmeyen kaynakları dahil etmeniz gerekir.

---

## 🏗️ Proje Mimarisi ve Dizin Yapısı

Proje, temiz mimari (Clean Architecture) ve modüler servis yapısı gözetilerek Flutter (Dart) ve Android Native (Kotlin) katmanlarında geliştirilmiştir.

```
lib/
├── models/             # Veri modelleri (SongItem, PlaylistItem)
├── screens/            # Uygulama ekranları (Player, Playlists, Folders, EQ, Smart vs.)
├── services/           # Arka plan servisleri (Player, Library, EQ, ID3, Storage, Stats)
├── theme/              # Renk paletleri ve görsel stiller (CobbleStyle, Palette)
└── widgets/            # Yeniden kullanılabilir özel widget'lar (MiniPlayer, MarqueeText vb.)

android/app/src/main/kotlin/com/cobblestone/cobblestone/
├── BiquadEqProcessor.kt # Yerel EQ işleme motoru
├── BrowseTree.kt        # Android Auto medya ağacı yapısı
├── CobbleMedia.kt       # Medya öğeleri entegrasyonu
├── CoverResolver.kt     # Yüksek hızlı albüm kapağı çözücü
├── LibraryScanService.kt # Yerel depolama tarama servisi
└── PlaybackService.kt   # Arka plan medya oynatma ve bildirim yönetimi
```

---

## 🚀 Kurulum ve Çalıştırma

### Gereksinimler

- **Flutter SDK:** ^3.0.0
- **Android SDK:** API 21 veya üzeri
- **Dart SDK:** ^3.0.0

### Geliştirme Ortamında Çalıştırma

1. Repoyu klonlayın:

```bash
git clone https://github.com/C-Stone-Labs/Cobblestone.git
cd Cobblestone
```

2. Bağımlılıkları yükleyin:

```bash
flutter pub get
```

3. Uygulamayı bağlı bir cihazda veya emülatörde çalıştırın:

```bash
flutter run
```

---

## 📦 APK Üretme ve GitHub Release Hazırlığı

GitHub üzerinde **Release** paylaşmak veya cihazınıza yüklemek üzere APK dosyası üretmek için aşağıdaki adımları izleyebilirsiniz.

### 1. Release APK Oluşturma

Terminalde proje dizinindeyken şu komutu çalıştırın:

```bash
flutter build apk --release
```

Bu komut mimariye göre optimize edilmiş tek bir APK dosyası üretir. Dosya konumu: `build/app/outputs/flutter-apk/app-release.apk`

### 2. İşlemci Mimarisine Göre Ayrılmış (Split) APK Üretme (İsteğe Bağlı)

Dosya boyutunu küçültmek ve her cihaza özel APK üretmek isterseniz:

```bash
flutter build apk --split-per-abi
```

Bu komut çıktı klasöründe `arm64-v8a`, `armeabi-v7a` ve `x86_64` için ayrı APK'lar oluşturur.

---

## 🏷️ GitHub'da Release Oluşturma

1. GitHub reponuza gidin ve sağ taraftaki **Releases** bölümünden **"Create a new release"** seçeneğine tıklayın.
2. Yeni bir etiket (tag) belirleyin (Örn: `v1.0.0`).
3. Sürüm başlığını ve değişiklik günlüğünü (Changelog) yazın.
4. `build/app/outputs/flutter-apk/app-release.apk` yolunda oluşan **APK** dosyasını yükleme alanına sürükleyip bırakın.
5. **Publish release** butonuna basarak yayınlayın.

---

## 📜 Lisans

Bu proje **GNU General Public License v3.0 (GPLv3)** ile lisanslanmıştır. Detaylar için "LICENSE" dosyasına göz atabilirsiniz.
