// Makes every sound and music loop in assets/sounds/ (spec-12), so the game's
// audio is our own: nothing bought or downloaded. Run from the project root:
//
//   dart run tool/make_sounds.dart
//
// Mono 16-bit WAV at 22050 Hz. Music loops wrap their tails around to the
// start, so they loop without a click.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const rate = 22050;
final _rng = Random(7);

void main() {
  final dir = Directory('assets/sounds')..createSync(recursive: true);
  void save(String name, List<double> s, {double peak = 0.85}) {
    final file = File('${dir.path}/$name.wav')..writeAsBytesSync(_wav(_normalize(s, peak)));
    stdout.writeln('${file.path}  ${(s.length / rate).toStringAsFixed(2)}s');
  }

  save('tap', tap());
  save('clack', clack());
  save('word', notes([76, 83], 0.09, 0.45, bell));
  save('magic', notes([72, 76, 79, 84], 0.08, 0.7, bell));
  save('coin', coin());
  save('whoosh', whoosh(), peak: 0.6);
  save('reward', notes([67, 72, 76, 79, 84], 0.09, 0.9, bell));
  save('building', fanfare());
  save('music_village', village(), peak: 0.7);
  save('music_daily', daily(), peak: 0.7);
  save('music_time_attack', timeAttack(), peak: 0.7);
}

// ---- building blocks ----------------------------------------------------------

double hz(num midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

List<double> silence(double seconds) => List<double>.filled((seconds * rate).round(), 0);

/// Adds [src] into [dst] at [at] seconds; with [wrap], what runs past the
/// end comes back in at the start (for loops).
void mix(List<double> dst, List<double> src, double at, {double gain = 1, bool wrap = false}) {
  final start = (at * rate).round();
  for (int i = 0; i < src.length; i++) {
    var j = start + i;
    if (j >= dst.length) {
      if (!wrap) break;
      j %= dst.length;
    }
    dst[j] += src[i] * gain;
  }
}

/// A bell or music-box note: a few sine partials with a quick attack and a
/// long, soft decay.
List<double> bell(double f, double len) {
  final n = (len * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / rate;
    final env = min(1.0, t / 0.004) * exp(-t * 5.5);
    return env *
        (sin(2 * pi * f * t) + 0.35 * sin(2 * pi * 2 * f * t) * exp(-t * 6) + 0.12 * sin(2 * pi * 3.01 * f * t) * exp(-t * 9));
  });
}

/// A soft plucked string.
List<double> pluck(double f, double len) {
  final n = (len * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / rate;
    final env = min(1.0, t / 0.006) * exp(-t * 4);
    return env * (sin(2 * pi * f * t) + 0.25 * sin(2 * pi * 2 * f * t) * exp(-t * 8) + 0.1 * sin(2 * pi * 3 * f * t) * exp(-t * 12));
  });
}

/// A warm pad: slow swell in and out, slightly detuned for width.
List<double> pad(double f, double len) {
  final n = (len * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / rate;
    final env = min(1.0, t / 0.5) * min(1.0, (len - t) / 0.6).clamp(0.0, 1.0);
    return env * (sin(2 * pi * f * t) + sin(2 * pi * f * 1.004 * t) + 0.3 * sin(2 * pi * 2 * f * t)) / 2.3;
  });
}

/// A round, soft bass note.
List<double> bass(double f, double len) {
  final n = (len * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / rate;
    final env = min(1.0, t / 0.01) * exp(-t * 3) * min(1.0, (len - t) / 0.05).clamp(0.0, 1.0);
    return env * (sin(2 * pi * f * t) + 0.2 * sin(2 * pi * 2 * f * t));
  });
}

/// A soft brush on the beat (filtered noise).
List<double> shaker(double len) {
  final n = (len * rate).round();
  var last = 0.0;
  return List<double>.generate(n, (i) {
    final t = i / rate;
    final white = _rng.nextDouble() * 2 - 1;
    final hp = white - last; // a little high-pass
    last = white;
    return hp * exp(-t * 40) * 0.5;
  });
}

/// Notes one after another, each [step] seconds apart, ringing for [ring].
List<double> notes(List<int> midi, double step, double ring, List<double> Function(double, double) voice) {
  final out = silence(step * (midi.length - 1) + ring + 0.05);
  for (int i = 0; i < midi.length; i++) {
    mix(out, voice(hz(midi[i]), ring), i * step, gain: 0.8 + 0.05 * i);
  }
  return out;
}

// ---- sound effects -----------------------------------------------------------

/// A soft button tap.
List<double> tap() {
  final n = (0.05 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / rate;
    return exp(-t * 90) * (sin(2 * pi * 900 * t) + 0.4 * sin(2 * pi * 1800 * t)) + (_rng.nextDouble() - 0.5) * exp(-t * 300) * 0.3;
  });
}

/// A wooden tile set down on the board.
List<double> clack() {
  final n = (0.09 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / rate;
    final body = exp(-t * 55) * (sin(2 * pi * 620 * t) + 0.6 * sin(2 * pi * 1240 * t + 1) + 0.3 * sin(2 * pi * 1870 * t));
    final knock = (_rng.nextDouble() - 0.5) * exp(-t * 220) * 0.9;
    return body + knock;
  });
}

/// Two coins clinking.
List<double> coin() {
  final out = silence(0.32);
  List<double> ping(double f) => List<double>.generate((0.25 * rate).round(), (i) {
        final t = i / rate;
        return exp(-t * 18) * (sin(2 * pi * f * t) + 0.5 * sin(2 * pi * f * 1.5 * t));
      });
  mix(out, ping(1975), 0);
  mix(out, ping(2637), 0.07, gain: 0.8);
  return out;
}

/// A soft whoosh for swiping pages.
List<double> whoosh() {
  final n = (0.28 * rate).round();
  var lp = 0.0;
  return List<double>.generate(n, (i) {
    final t = i / rate;
    final env = sin(pi * t / 0.28);
    final a = 0.03 + 0.12 * env; // the filter opens as it swells
    lp += a * ((_rng.nextDouble() * 2 - 1) - lp);
    return lp * env;
  });
}

/// A new building: ta-da!
List<double> fanfare() {
  final out = silence(1.6);
  for (final (m, at) in [(67, 0.0), (72, 0.12), (76, 0.24)]) {
    mix(out, pluck(hz(m), 0.3), at, gain: 0.8);
    mix(out, bell(hz(m + 12), 0.3), at, gain: 0.25);
  }
  for (final m in [72, 76, 79, 84]) {
    mix(out, pad(hz(m), 1.2), 0.38, gain: 0.45);
    mix(out, bell(hz(m), 1.2), 0.38, gain: 0.35);
  }
  mix(out, bass(hz(48), 1.1), 0.38, gain: 0.6);
  return out;
}

// ---- music ---------------------------------------------------------------------

/// A loop over a chord progression: soft pad, a bass note per bar, and a
/// gentle melody walking a pentatonic scale.
List<double> loop({
  required int bpm,
  required List<List<int>> chords, // one chord per bar, MIDI notes
  required List<int> scale,
  required List<double> Function(double, double) lead,
  required double leadEvery, // beats between melody notes
  double restChance = 0.3,
  bool bassEighths = false,
  bool brush = false,
  int seed = 1,
}) {
  final rng = Random(seed);
  final beat = 60 / bpm;
  final bar = beat * 4;
  final out = silence(bar * chords.length);
  var pos = rng.nextInt(scale.length);
  for (int b = 0; b < chords.length; b++) {
    final c = chords[b];
    final t0 = b * bar;
    for (final m in c) {
      mix(out, pad(hz(m), bar + 0.4), t0, gain: 0.22, wrap: true);
    }
    if (bassEighths) {
      for (int e = 0; e < 8; e++) {
        mix(out, bass(hz(c.first - 12 + (e % 4 == 3 ? 7 : 0)), beat / 2), t0 + e * beat / 2, gain: 0.5, wrap: true);
      }
    } else {
      mix(out, bass(hz(c.first - 12), bar * 0.9), t0, gain: 0.55, wrap: true);
      mix(out, bass(hz(c.first - 5), beat * 1.5), t0 + beat * 2, gain: 0.35, wrap: true);
    }
    if (brush) {
      for (int e = 0; e < 8; e++) {
        mix(out, shaker(0.08), t0 + e * beat / 2, gain: e.isEven ? 0.35 : 0.2, wrap: true);
      }
    }
    for (double x = 0; x < 4 - 0.001; x += leadEvery) {
      if (rng.nextDouble() < restChance && x > 0) continue;
      // Mostly small steps; land on a chord tone at the start of the bar.
      pos = (pos + [-2, -1, -1, 1, 1, 2, 0][rng.nextInt(7)]).clamp(0, scale.length - 1);
      var note = scale[pos];
      if (x == 0) {
        final tones = scale.where((s) => c.any((m) => (m - s) % 12 == 0)).toList();
        if (tones.isNotEmpty) {
          note = tones.reduce((a, s) => (s - scale[pos]).abs() < (a - scale[pos]).abs() ? s : a);
          pos = scale.indexOf(note);
        }
      }
      mix(out, lead(hz(note), beat * leadEvery * 2.2), t0 + x * beat, gain: 0.5, wrap: true);
    }
  }
  return out;
}

// C major pentatonic, two octaves.
const _cPenta = [67, 69, 72, 74, 76, 79, 81, 84, 86];

/// Your village: calm and warm. C - Am - F - G, twice.
List<double> village() => loop(
      bpm: 80,
      chords: [
        [60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62],
        [60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62],
      ],
      scale: _cPenta,
      lead: pluck,
      leadEvery: 1,
      restChance: 0.35,
      seed: 3,
    );

/// The Daily puzzle: a thoughtful music box. F - Dm - Bb - C, twice.
List<double> daily() => loop(
      bpm: 72,
      chords: [
        [53, 57, 60], [50, 53, 57], [46, 50, 53], [48, 52, 55],
        [53, 57, 60], [50, 53, 57], [46, 50, 53], [48, 52, 55],
      ],
      scale: [72, 74, 77, 79, 81, 84, 86, 89],
      lead: bell,
      leadEvery: 1,
      restChance: 0.45,
      seed: 11,
    );

/// Time Attack: livelier, with a moving bass and a brush beat.
/// C - G - Am - F, twice.
List<double> timeAttack() => loop(
      bpm: 126,
      chords: [
        [60, 64, 67], [55, 59, 62], [57, 60, 64], [53, 57, 60],
        [60, 64, 67], [55, 59, 62], [57, 60, 64], [53, 57, 60],
      ],
      scale: _cPenta,
      lead: pluck,
      leadEvery: 0.5,
      restChance: 0.4,
      bassEighths: true,
      brush: true,
      seed: 5,
    );

// ---- WAV ---------------------------------------------------------------------

List<double> _normalize(List<double> s, double peak) {
  final m = s.fold<double>(0, (a, v) => max(a, v.abs()));
  return m == 0 ? s : [for (final v in s) v / m * peak];
}

Uint8List _wav(List<double> s) {
  final data = ByteData(44 + s.length * 2);
  void str(int at, String v) {
    for (int i = 0; i < v.length; i++) {
      data.setUint8(at + i, v.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + s.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, s.length * 2, Endian.little);
  for (int i = 0; i < s.length; i++) {
    data.setInt16(44 + i * 2, (s[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
