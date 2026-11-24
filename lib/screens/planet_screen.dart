import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../letterra/globe_view.dart';
import '../letterra/planet.dart';
import '../letterra/planet_data.dart';
import '../settings/settings_controller.dart';
import '../sound/sound_service.dart';
import '../ui/chunky_button.dart';
import '../ui/tokens.dart';
import 'family_screens.dart' show VisitVillageScreen;
import 'infinite_estate_screen.dart';

/// Planet mode (spec-18b): the whole of Letterra on its own page. Drag to
/// spin, pinch or + / - to zoom, and tap a village to fly down into it. Coming
/// back from the village returns here.
class PlanetScreen extends ConsumerStatefulWidget {
  const PlanetScreen({super.key, required this.data, required this.onVisited});

  /// Home keeps this up to date.
  final ValueListenable<PlanetData?> data;

  /// Called after a village closes, so Home can read the save again.
  final Future<void> Function() onVisited;

  @override
  ConsumerState<PlanetScreen> createState() => _PlanetScreenState();
}

class _PlanetScreenState extends ConsumerState<PlanetScreen> {
  final _globe = GlobalKey<GlobeViewState>();
  bool _diving = false;

  Future<void> _dive(PlanetData data, int slot) async {
    if (_diving) return;
    setState(() => _diving = true);
    final reduce = ref.read(settingsProvider).reduceMotion;
    if (!reduce) {
      ref.read(soundProvider).play(Sfx.whoosh);
      await _globe.currentState?.diveTo(slot);
      if (!mounted) return;
    }
    final player = data.players[slot];
    final screen = slot == data.mySlot || player == null
        ? const InfiniteEstateScreen()
        : VisitVillageScreen(player: player) as Widget;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: Duration(milliseconds: reduce ? 0 : 280),
      reverseTransitionDuration: Duration(milliseconds: reduce ? 0 : 220),
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    if (!mounted) return;
    setState(() => _diving = false);
    _globe.currentState?.showWhole(slot);
    await widget.onVisited();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = ref.watch(settingsProvider.select((s) => s.reduceMotion));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        backgroundColor: kGlobeSky,
        body: ValueListenableBuilder<PlanetData?>(
          valueListenable: widget.data,
          builder: (context, data, _) {
            if (data == null) return const SizedBox.shrink();
            return Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  ignoring: _diving,
                  child: GlobeView(
                    key: _globe,
                    villages: data.villages,
                    takenSlots: data.takenSlots,
                    focusSlot: data.mySlot,
                    isHushed: data.isHushed,
                    reduceMotion: reduce,
                    alwaysPan: true,
                    showZoomButtons: !_diving,
                    zoomButtonsBottom: MediaQuery.paddingOf(context).bottom + 84,
                    onVillageTap: (s) => _dive(data, s),
                  ),
                ),
                // Out of the way while flying down.
                if (!_diving)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(WSize.screenPadding),
                      child: Column(
                        children: [
                          Row(children: [
                            ChunkyIconButton(
                              icon: Icons.arrow_back,
                              tooltip: 'Back',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Expanded(
                              child: Text(
                                kPlanetName,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: WText.heading.copyWith(fontSize: 28, color: WColors.ink),
                              ),
                            ),
                            const SizedBox(width: WSize.tapTarget),
                          ]),
                          const Spacer(),
                          ChunkyButton(
                            label: 'Find my village',
                            icon: Icons.my_location,
                            kind: ChunkyKind.mode,
                            modeColor: WColors.sun,
                            size: ChunkySize.big,
                            expand: true,
                            onPressed: () => _globe.currentState?.flyHome(data.mySlot),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
