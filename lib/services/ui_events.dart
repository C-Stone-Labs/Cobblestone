import 'package:flutter/material.dart';

/// v5.1.3: mini oynatıcının üstüne açılan MENÜLERDEN otomatik kaçması için
/// uygulama genelinde "yarı saydam rota" sayacı. Alt sayfalar (⋮ menüsü),
/// diyaloglar ve seçim çubuğu sayfaları saydam rota olarak açılır; sayaç
/// artar, mini oynatıcı kayarak iner. Menü kapanınca sayaç düşer, mini
/// oynatıcı geri döner. Tek mekanizma — her menüyü tek tek sarmaya gerek
/// yok, kaçarken bug'a girecek ölçüm/kural yok.
final ValueNotifier<int> overlayMenuCount = ValueNotifier<int>(0);

bool _isOverlayMenu(Route? route) =>
    route is TransitionRoute && !route.opaque;

/// Navigator gözlemcisi: saydam (menü/diyalog) rotaları sayar.
class OverlayMenuObserver extends RouteObserver<Route> {
  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isOverlayMenu(route)) overlayMenuCount.value++;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (_isOverlayMenu(route)) overlayMenuCount.value--;
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_isOverlayMenu(route)) overlayMenuCount.value--;
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (_isOverlayMenu(oldRoute)) overlayMenuCount.value--;
    if (_isOverlayMenu(newRoute)) overlayMenuCount.value++;
  }
}

/// v5.1.3: alt ray yükseklikleri (ekranın altından, px). Mini oynatıcı
/// ve seçim çubuğu görünürken kendi kapladığı yüksekliği yazar; bildirim
/// kutusu en yüksek rayın ÜSTÜNDE durur (yok olmaz, sadece yer açar).
final ValueNotifier<double> miniRailPx = ValueNotifier<double>(0);
final ValueNotifier<double> selectionRailPx = ValueNotifier<double>(0);

/// Bildirim kutusunun ÜST kenarı (ekranın altından px). Kutu açıkken
/// yayınlanır; mini oynatıcı bu sayıya bakarak kutuyla temas etmeyecek
/// kadar kendini yukarı alır. Kapalıyken 0'dır.
final ValueNotifier<double> toastTopPx = ValueNotifier<double>(0);
