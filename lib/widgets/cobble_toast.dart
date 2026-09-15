import 'dart:async';

import 'package:flutter/material.dart';

import '../services/theme_controller.dart';
import '../theme/cobble_style.dart';
import '../services/ui_events.dart';

/// v5.1.3: uygulama genelinde TEK bildirim tasarımı.
///
/// Kutunun kuralları (katman koreografisi):
/// • Material sarmalıyla varsayılan stil sızmaz (sarı altı çizgi yok).
/// • Yumuşak animasyonla gelir; parmak üstündeyken süre durur, bırakınca
///   0,7 sn sonra kapanır.
/// • Aşağı doğru İTİLEBİLİR — parmağı izler, yeterince itilirse kapanır.
/// • Yerleşimi: ekranın altındaki sabit zemin (sekmeler + sistem çubuğu)
///   ve görünür katmanların (mini oynatıcı, seçim çubuğu) ÜSTÜNDE durur;
///   hiçbirinin üstüne binmez. Üst kenarını [toastTopPx] ile yayınlar —
///   mini oynatıcı buna bakarak kendini yukarı alır.
/// • Üstte menü/sheet/diyalog açıkken bekler, kapanınca görünür
///   (açık sayfayı örtmez).
void showCobbleToast(
  BuildContext context,
  String message, {
  IconData? icon,
  Color? accent,
}) {
  CobbleToastManager.instance.show(context, message, icon: icon, accent: accent);
}

class _ToastData {
  const _ToastData(this.message, this.icon, this.accent);
  final String message;
  final IconData? icon;
  final Color? accent;
}

class CobbleToastManager {
  CobbleToastManager._() {
    // Menüler (sheet/diyalog) tamamen kapanınca bekleyen kutu gösterilir.
    overlayMenuCount.addListener(_onMenusChanged);
  }
  static final instance = CobbleToastManager._();

  final GlobalKey<CobbleToastHostState> _key = GlobalKey();
  OverlayEntry? _entry;
  _ToastData? _pending;
  OverlayState? _overlay;


  void _onMenusChanged() {
    if (overlayMenuCount.value <= 0 && _pending != null) {
      final d = _pending!;
      _pending = null;
      _present(d);
    }
  }

  void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? accent,
  }) {
    // v5.1.3: her zaman KÖK overlay — sekme içi küçük koordinat
    // alanına takılırsa mini oynatıcı yanlış hesap yapıp uçar.
    _overlay = Overlay.maybeOf(context, rootOverlay: true) ?? _overlay;
    if (_overlay == null) return;
    final data = _ToastData(message, icon, accent);
    // Üstte menü/diyalog açıkken hemen gösterilmez (örtebilir).
    if (overlayMenuCount.value > 0 && _entry == null) {
      _pending = data;
      return;
    }
    _pending = null;
    _present(data);
  }

  void _present(_ToastData d) {
    final overlay = _overlay;
    if (overlay == null) return;
    _last ??= d;
    _last = d;
    if (_entry == null) {
      _entry = OverlayEntry(
        builder: (_) => CobbleToastHost(key: _key, manager: this),
      );
      overlay.insert(_entry!);
    } else {
      _key.currentState?.renew(d);
    }
  }

  _ToastData? _last;

  _ToastData? get current => _last;


  void onFinished() {
    _entry?.remove();
    _entry = null;
    toastTopPx.value = 0;
  }
}

class CobbleToastHost extends StatefulWidget {
  const CobbleToastHost({super.key, required this.manager});

  final CobbleToastManager manager;

  @override
  State<CobbleToastHost> createState() => CobbleToastHostState();
}

class CobbleToastHostState extends State<CobbleToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: CobbleMotion.normal,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _in,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  Timer? _timer;
  final Set<int> _pointers = {};
  bool _closing = false;
  double _drag = 0;
  double _floor = 0;
  DateTime? _expiresAt;
  DateTime? _touchStart;
  final GlobalKey _boxKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _in.forward();
    _arm(const Duration(milliseconds: 2600));
  }

  /// Üst üste yeni bildirim gelirse: süre baştan, içerik tazelenir.
  void renew(_ToastData d) {
    widget.manager._last = d;
    if (_closing) {
      _closing = false;
      _in.forward();
    }
    _drag = 0;
    _arm(const Duration(milliseconds: 2600));
    setState(() {});
  }

  void _arm(Duration d) {
    _timer?.cancel();
    _expiresAt = DateTime.now().add(d);
    _timer = Timer(d, _expire);
  }

  void _expire() {
    // Parmak üstündeyken süre dolsa bile kapanmaz; bırakınca 0,7 sn.
    if (_pointers.isNotEmpty || _drag > 0) return;
    _close();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _in.reverse().whenCompleteOrCancel(() {
      if (mounted) widget.manager.onFinished();
    });
  }

  void _holdStart(PointerDownEvent e) {
    _pointers.add(e.pointer);
    _touchStart = DateTime.now();
    _timer?.cancel();
  }

  void _holdEnd(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty && !_closing) {
      final held = _touchStart != null &&
          DateTime.now().difference(_touchStart!) >=
              const Duration(milliseconds: 350);
      if (held) {
        // Gerçek TUTMA: bırakınca 0,7 sn sonra kapanır.
        _arm(const Duration(milliseconds: 700));
      } else {
        // Hızlı dokunuş: kutu tepki vermez, kalan süresinden devam eder.
        final remain =
            _expiresAt?.difference(DateTime.now()) ?? Duration.zero;
        _arm(remain.isNegative || remain == Duration.zero
            ? const Duration(milliseconds: 700)
            : remain);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    toastTopPx.value = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final d = m.current ?? const _ToastData('', null, null);
    final p = ThemeController.instance.paletteNotifier.value;
    final ac = d.accent ?? p.orange;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 0,
      child: ListenableBuilder(
        // v5.1.3: kutu açıldığında mini oynatıcı zaten gizlenir; kutunun
        // zemini yalnız sekmeler + seçim çubuğudur. Mini rayı OKUMAZ —
        // döngü imkânsız.
        listenable: selectionRailPx,
        builder: (context, _) {
          final navFloor =
              80 + MediaQuery.viewPaddingOf(context).bottom + 10;
          var floor = navFloor;
          if (selectionRailPx.value > 0) {
            floor = floor > selectionRailPx.value + 10
                ? floor
                : selectionRailPx.value + 10;
          }
          _floor = floor;
          // Üst kenar (ekranın altından px) yayınlanır — mini oynatıcı
          // teması bu tek sayıya bakarak önler.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _closing) return;
            final ro = _boxKey.currentContext?.findRenderObject();
            if (ro is RenderBox && ro.hasSize) {
              final top = floor + ro.size.height;
              if (toastTopPx.value != top) toastTopPx.value = top;
            }
          });
          return AnimatedPadding(
            padding: EdgeInsets.only(bottom: floor),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _in.drive(
                  Tween(begin: const Offset(0, 0.3), end: Offset.zero),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (det) {
                    // Parmakla CANLI izler (aşağı ve yukarı); eşik geçilirse
                    // parmak kalkmadan kapanır — hızlı da yavaş da.
                    if (_closing) return;
                    setState(() => _drag += det.delta.dy);
                    if (_drag >= 56) _close();
                  },
                  onVerticalDragEnd: (det) {
                    if (_closing) return;
                    if (det.velocity.pixelsPerSecond.dy > 800 &&
                        _drag > 18) {
                      _close();
                    } else if (_drag != 0) {
                      // Yaylanıp yerine döner (yukarı çekilince de döner).
                      setState(() => _drag = 0);
                    }
                  },
                  child: Listener(
                    onPointerDown: _holdStart,
                    onPointerUp: _holdEnd,
                    onPointerCancel: _holdEnd,
                    child: AnimatedSlide(
                      key: _boxKey,
                      offset: Offset(
                        0,
                        (_drag / 110).clamp(0.0, 1.15),
                      ),
                      duration: Duration(
                        milliseconds: _drag != 0 ? 16 : 220,
                      ),
                      curve: Curves.easeOut,
                      // Material sarmalı: Overlay'de varsayılan metin stili
                      // (sarı altı çizgi) sızmasını kesin engeller.
                      child: Material(
                        type: MaterialType.transparency,
                        child: Container(
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(CobbleRadii.card),
                          border: Border.all(color: p.cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: ac.withValues(alpha: 0.16),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                d.icon ?? Icons.music_note_rounded,
                                color: ac,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                d.message,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
