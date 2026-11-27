import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import 'planet.dart';

// The planet's art (spec-18b): a painted map of the land seen from above and
// one sheet of small ready-made 3D pictures. Both are made by
// tool/globe_art/ (make_map.py and sprites.html).

/// The map pictures cover these board rows/columns (the rest is plain sea).
const double kMapFrom = 100;
const double kMapSpan = 300;

/// The pictures on assets/globe/sprites.png, left to right, top to bottom.
enum GlobeSprite {
  oak,
  oakSmall,
  pine,
  pineSmall,
  puff,
  puffWide,
  cloud,
  boulder,
  peakA,
  peakB,
  peakC,
  ruin,
  lantern,
  port,
  boatGold,
  flagGold,
  houseRed,
  houseBlue,
  houseGold,
  houseGreen,
  barn,
  mill,
  well,
  star,
  whale,
  octopus,
  lamp,
  boatCoral,
  boatGreen,
  flagCoral,
  flagGreen,
  housePurple,
  farm,
  tower,
  bridge,
  garden,
  flagBlank;

  static const double cell = 384;

  ui.Rect get rect => ui.Rect.fromLTWH((index % 8) * cell, (index ~/ 8) * cell, cell, cell);
}

class GlobeArt {
  GlobeArt._(this._land, this._bays, this.sprites);

  final ui.Image _land;
  final ui.Image _bays;
  final ui.Image sprites;

  /// The art once it is loaded (null until then, and always in tests).
  static GlobeArt? loaded;
  static Future<GlobeArt>? _loading;

  static Future<GlobeArt> load() => _loading ??= _read();

  static Future<GlobeArt> _read() async {
    Future<ui.Image> image(String name) async {
      final data = await rootBundle.load('assets/globe/$name');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    }

    return loaded = GlobeArt._(await image('map_land.jpg'), await image('map_bays.jpg'), await image('sprites.png'));
  }

  final _maps = <int, ui.Image>{};

  /// The map with land at the [taken] harbors and open bays at the others.
  ui.Image mapFor(Set<int> taken) {
    var key = 0;
    for (final s in taken) {
      key |= 1 << s;
    }
    return _maps.putIfAbsent(key, () {
      final w = _land.width.toDouble();
      final centre = ui.Offset(w * (kLanternCol + 0.5 - kMapFrom) / kMapSpan, w * (kLanternRow + 0.5 - kMapFrom) / kMapSpan);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImage(_bays, ui.Offset.zero, ui.Paint());
      for (final s in taken) {
        const half = math.pi / kHarborSlots;
        ui.Offset at(double lon) => centre + ui.Offset(math.sin(lon), math.cos(lon)) * w;
        final a = slotAngle(s);
        canvas.save();
        canvas.clipPath(ui.Path()..addPolygon([centre, at(a - half), at(a), at(a + half)], true));
        canvas.drawImage(_land, ui.Offset.zero, ui.Paint());
        canvas.restore();
      }
      return recorder.endRecording().toImageSync(_land.width, _land.height);
    });
  }
}

/// How thickly the planet draws the Hush over still-covered land, 0-1. (Inside
/// the village the fog is unchanged; this is only the view from space.)
double hushThickness(Band band) => switch (band) {
      Band.sunnyShore || Band.deep => 0,
      Band.meadow => 0.10,
      Band.whisperWoods => 0.42,
      Band.echoMountains => 0.75,
      _ => 1,
    };

/// Something standing on the planet: a tree, a peak, a puff of the Hush.
class GlobeDecor {
  const GlobeDecor(this.row, this.col, this.x, this.y, this.z, this.sprite, this.cells, {this.hush = false});

  final int row, col;

  /// Where it stands on the unit sphere.
  final double x, y, z;
  final GlobeSprite sprite;

  /// Width of the whole picture, in board cells.
  final double cells;

  /// A puff of the Hush: shown only while its land is still covered.
  final bool hush;
}

final _decorCache = <int, List<GlobeDecor>>{};

/// Everything that stands on the land for these taken harbors (the same every
/// time).
List<GlobeDecor> globeDecorFor(Set<int> taken) {
  var key = 0;
  for (final s in taken) {
    key |= 1 << s;
  }
  return _decorCache.putIfAbsent(key, () {
    final rnd = math.Random(18);
    final out = <GlobeDecor>[];
    void put(double row, double col, GlobeSprite sprite, double cells, {bool hush = false}) {
      final r = row.round(), c = col.round();
      if (bandAt(r, c) == Band.deep || isBay(r, c, taken)) return;
      final dr = row - kLanternRow, dc = col - kLanternCol;
      final d = math.sqrt(dr * dr + dc * dc);
      final lat = math.pi / 2 * (1 - d / kHarborDistance), lon = math.atan2(dc, dr);
      out.add(GlobeDecor(r, c, math.cos(lat) * math.sin(lon), math.sin(lat), math.cos(lat) * math.cos(lon), sprite, cells,
          hush: hush));
    }

    // Rings round the Lantern, so things are as far apart on the globe as on
    // the ground (the board's disc is squeezed towards the shore).
    void rings(double from, double to, double gap, void Function(double r, double c, double u) place) {
      for (var d = from; d < to; d += gap) {
        final lat = math.pi / 2 * (1 - d / kHarborDistance);
        final around = 4 * kHarborDistance * math.cos(lat).abs();
        final n = math.max(1, (around / gap).round());
        for (var i = 0; i < n; i++) {
          final lon = (i + rnd.nextDouble() * 0.8) * 2 * math.pi / n;
          final dd = d + (rnd.nextDouble() - 0.5) * gap;
          place(kLanternRow + dd * math.cos(lon), kLanternCol + dd * math.sin(lon), rnd.nextDouble());
        }
      }
    }

    rings(96, 115, 7, (r, c, u) {
      if (u < 0.55) put(r, c, u < 0.3 ? GlobeSprite.oak : GlobeSprite.oakSmall, 13);
    });
    rings(70, 95, 3.6, (r, c, u) {
      put(r, c, GlobeSprite.values[u < 0.4 ? 2 : (u < 0.7 ? 3 : (u < 0.85 ? 0 : 1))], 13 + u * 3);
    });
    rings(47, 63, 8, (r, c, u) {
      if (u < 0.2) put(r, c, GlobeSprite.ruin, 13);
      if (u > 0.5) put(r, c, u > 0.75 ? GlobeSprite.boulder : GlobeSprite.oakSmall, 12);
    });
    rings(22, 44, 7, (r, c, u) {
      put(r, c, u < 0.4 ? GlobeSprite.peakA : (u < 0.75 ? GlobeSprite.peakB : GlobeSprite.peakC), 14 + u * 7);
    });
    rings(8, 124, 5, (r, c, u) {
      // The Hush thins towards the shore, so the planet always shows where you
      // could go next instead of a blank white ball.
      if (rnd.nextDouble() > hushThickness(bandAt(r.round(), c.round()))) return;
      put(r, c, u < 0.5 ? GlobeSprite.puff : GlobeSprite.puffWide, 11 + u * 9, hush: true);
    });
    return out;
  });
}
