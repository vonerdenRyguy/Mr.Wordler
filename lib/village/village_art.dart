import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

// The Village view's building art (assets/village/): one sprite per magic
// word, and where it sits on its word (buildings.json). Loaded once and
// shared.

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

class BuildingSprite {
  BuildingSprite(this.meta, this.image, this._pixels);

  final SpriteMeta meta;
  final ui.Image image;
  final ByteData? _pixels;

  /// Whether the sprite pixel at (x, y) is solid enough to tap. Unknown
  /// pixels (art not decoded) count as solid.
  bool opaqueAt(int x, int y) {
    final pixels = _pixels;
    if (pixels == null) return true;
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) return false;
    return pixels.getUint8((y * image.width + x) * 4 + 3) > 40;
  }
}

class VillageArt {
  VillageArt._(this.meta, this.sprites);

  final Map<String, SpriteMeta> meta;
  final Map<String, BuildingSprite> sprites;

  static Future<Map<String, SpriteMeta>>? _metaLoading;
  static Future<VillageArt>? _loading;

  /// Just the placement data (small JSON, no image decoding).
  static Future<Map<String, SpriteMeta>> loadMeta() => _metaLoading ??= _readMeta();

  /// Placement data plus decoded sprites.
  static Future<VillageArt> load() => _loading ??= _readAll();

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

  static Future<VillageArt> _readAll() async {
    final meta = await loadMeta();
    final sprites = <String, BuildingSprite>{};
    for (final entry in meta.entries) {
      final data = await rootBundle.load(entry.value.spritePath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      sprites[entry.key] = BuildingSprite(entry.value, image, pixels);
    }
    return VillageArt._(meta, sprites);
  }
}
