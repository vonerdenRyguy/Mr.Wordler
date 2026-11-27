import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

// The buildings' tap-card pictures (assets/village/, listed in
// buildings.json). Loaded once and shared.

/// Where a building's sprite sits: the PNG's size and the pixel that goes
/// on the ground at the middle of the word.
class SpriteMeta {
  const SpriteMeta({
    required this.anchorX,
    required this.anchorY,
    required this.width,
    required this.height,
    required this.spritePath,
    required this.cardPath,
  });

  final double anchorX;
  final double anchorY;
  final int width;
  final int height;
  final String spritePath;
  final String cardPath;
}

class VillageArt {
  VillageArt._();

  static Future<Map<String, SpriteMeta>>? _metaLoading;

  /// Just the placement data (small JSON, no image decoding).
  static Future<Map<String, SpriteMeta>> loadMeta() => _metaLoading ??= _readMeta();

  static Future<Map<String, SpriteMeta>> _readMeta() async {
    final json = jsonDecode(await rootBundle.loadString('assets/village/buildings.json')) as Map<String, dynamic>;
    final buildings = json['buildings'] as Map<String, dynamic>;
    return {
      for (final entry in buildings.entries)
        entry.key: SpriteMeta(
          anchorX: (entry.value['anchorX'] as num).toDouble(),
          anchorY: (entry.value['anchorY'] as num).toDouble(),
          width: entry.value['pngWidth'] as int,
          height: entry.value['pngHeight'] as int,
          spritePath: entry.value['sprite'] as String,
          cardPath: entry.value['card'] as String,
        ),
    };
  }
}
