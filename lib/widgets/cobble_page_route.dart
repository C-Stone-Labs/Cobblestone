import 'package:flutter/material.dart';

/// v5.1.3: iç ekran geçişi — yumuşak SOLMA (kaydırma yok).
/// Ayrı atmosferi olan iç ekranlar kaydırmalı geçişte iki atmosferi
/// üst üste gösterip "çift görüntü" sıçraması yaratıyordu; solumada
/// desenler örtüşür, geçiş görünmez derecede akıcı olur.
class CobblePageRoute<T> extends MaterialPageRoute<T> {
  CobblePageRoute({required super.builder, super.settings});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}
