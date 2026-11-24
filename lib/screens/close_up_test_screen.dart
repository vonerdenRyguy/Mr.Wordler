import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../letterra/close_up.dart';
import '../letterra/close_up_test_village.dart';
import '../letterra/globe_painter.dart';
import '../letterra/globe_view.dart';
import '../letterra/planet.dart';
import '../ui/chunky_button.dart';
import '../ui/tokens.dart';

/// Only in a test build: `--dart-define=CLOSEUP_TEST=true`.
const kCloseUpTest = bool.fromEnvironment('CLOSEUP_TEST');

/// The made-up village's letters and buildings, as the planet draws them.
List<GlobeVillage> closeUpTestVillages() {
  final letters = closeUpTestLetters();
  final runs = magicRunsOn(letters);
  return [
    GlobeVillage(
      slot: 0,
      name: 'Test village',
      letters: letters,
      buildingRuns: runs,
      buildings: [for (final r in runs.take(4)) r.word],
    ),
  ];
}

/// The close-up phone test (spec-22 C): a big made-up village, from the whole
/// planet down to its streets. Reads and saves nothing.
class CloseUpTestScreen extends StatefulWidget {
  const CloseUpTestScreen({super.key});

  @override
  State<CloseUpTestScreen> createState() => _CloseUpTestScreenState();
}

class _CloseUpTestScreenState extends State<CloseUpTestScreen> {
  final _globe = GlobalKey<GlobeViewState>();
  late final _villages = closeUpTestVillages();
  final _frames = <FrameTiming>[];
  final _report = ValueNotifier<String?>(null);
  bool _touring = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timed);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timed);
    _report.dispose();
    super.dispose();
  }

  void _timed(List<FrameTiming> timings) {
    if (_touring) _frames.addAll(timings);
  }

  Future<void> _tour() async {
    final globe = _globe.currentState;
    if (_touring || globe == null) return;
    _frames.clear();
    _report.value = null;
    setState(() => _touring = true);
    int cell(int row, int col) => row * kPlanetBoard + col;
    globe.showWhole(0);
    await globe.walkTo(cell(350, 250), kCloseUpMaxZoom, milliseconds: 3000);
    for (final (r, c) in const [(345, 235), (358, 240), (356, 265), (340, 262), (350, 250)]) {
      if (!mounted) return;
      await globe.walkTo(cell(r, c), kCloseUpMaxZoom);
    }
    if (!mounted) return;
    await globe.walkTo(cell(350, 250), 1, milliseconds: 3000);
    // The last timings arrive in a batch up to a second later.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _touring = false);
    if (_frames.isEmpty) return;
    double ms(Duration d) => d.inMicroseconds / 1000;
    double at(List<double> v, double q) => (v..sort())[((v.length - 1) * q).round()];
    final build = [for (final f in _frames) ms(f.buildDuration)];
    final raster = [for (final f in _frames) ms(f.rasterDuration)];
    final slow = _frames.where((f) => ms(f.buildDuration) > 16.7 || ms(f.rasterDuration) > 16.7).length;
    final text = '${_frames.length} pictures, $slow late (${(100 * slow / _frames.length).toStringAsFixed(1)}%). '
        'Usual ${at(build, 0.5).toStringAsFixed(1)} + ${at(raster, 0.5).toStringAsFixed(1)} ms, '
        'slow ones ${at(build, 0.95).toStringAsFixed(1)} + ${at(raster, 0.95).toStringAsFixed(1)} ms.';
    debugPrint('CLOSEUP $text');
    _report.value = text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kGlobeSky,
      body: Stack(fit: StackFit.expand, children: [
        GlobeView(
          key: _globe,
          villages: _villages,
          takenSlots: const {0},
          focusSlot: 0,
          isHushed: (r, c, _) => hushedByReach(r, c, 2),
          closeUp: true,
          alwaysPan: true,
          showTags: false,
          zoomButtonsBottom: MediaQuery.paddingOf(context).bottom + 96,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(WSize.screenPadding),
            child: Column(children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ChunkyIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: _report,
                builder: (context, text, _) => text == null
                    ? const SizedBox.shrink()
                    : Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        color: WColors.card,
                        child: Text(text, style: WText.body.copyWith(fontSize: 16, color: WColors.ink)),
                      ),
              ),
              const Spacer(),
              if (!_touring)
                ChunkyButton(
                  label: 'Measure',
                  icon: Icons.speed,
                  kind: ChunkyKind.mode,
                  modeColor: WColors.sun,
                  expand: true,
                  onPressed: _tour,
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
