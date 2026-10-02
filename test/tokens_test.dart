import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/ui/tokens.dart';

void main() {
  test('contrastRatio matches known WCAG values', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21.0, 0.01));
    expect(contrastRatio(WColors.ink, WColors.ink), closeTo(1.0, 0.001));
  });

  test('ink is readable on every background it sits on', () {
    for (final bg in [
      WColors.paper,
      WColors.card,
      WColors.tile,
      WColors.sky,
      WColors.coral,
      WColors.lilac,
      WColors.leaf,
      WColors.sun,
    ]) {
      expect(contrastRatio(WColors.ink, bg), greaterThanOrEqualTo(4.5), reason: 'ink on $bg');
    }
  });

  test('white is readable on grass and brick', () {
    expect(contrastRatio(WColors.white, WColors.grass), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(WColors.white, WColors.brick), greaterThanOrEqualTo(4.5));
  });

  test('muted text is readable on card and paper', () {
    expect(contrastRatio(WColors.muted, WColors.card), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(WColors.muted, WColors.paper), greaterThanOrEqualTo(4.5));
  });
}
