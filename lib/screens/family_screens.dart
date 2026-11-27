import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/word_runs.dart' show WordRun, settle;
import '../daily/daily_challenge_controller.dart';
import '../daily/word_of_the_day.dart';
import '../dictionary/word_speaker.dart';
import '../game/word_landing.dart' show wordCheckProvider;
import '../players/family_widgets.dart';
import '../players/family_word.dart';
import '../players/player_summary.dart';
import '../players/players.dart';
import '../settings/word_level.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import '../ui/wordler_scaffold.dart';
import '../village/magic_word.dart';
import '../village/structures.dart';
import '../village/village_art.dart';
import '../village/village_cards.dart';
import '../village/village_save.dart';
import '../village/village_save_migration.dart';
import '../dictionary/definition_service.dart';
import '../explore/fog.dart';
import '../letterra/globe_view.dart';
import '../letterra/globe_painter.dart';
import '../letterra/planet.dart';
import '../letterra/planet_data.dart';
import '../letterra/street.dart';
import '../settings/settings_controller.dart';
import 'daily_challenge_screen.dart';
import '../online/family_online_controller.dart';
import 'family_online_screens.dart';
import 'family_word_online_screens.dart';
import 'infinite_estate_screen.dart';
import 'players_screens.dart';

// The family screens (spec-07): today's family word, and the family page
// with everyone on this phone.

class FamilyWordScreen extends ConsumerStatefulWidget {
  const FamilyWordScreen({super.key});

  @override
  ConsumerState<FamilyWordScreen> createState() => _FamilyWordScreenState();
}

class _FamilyWordScreenState extends ConsumerState<FamilyWordScreen> {
  Map<String, PlayerSummary> _summaries = const {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final summaries = await loadSummaries(ref.read(playersProvider).players, DateTime.now());
    if (mounted) setState(() => _summaries = summaries);
  }

  Future<void> _play() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DailyChallengeScreen()));
    if (!mounted) return;
    _refresh();
    claimFamilyCoins(ref, context);
  }

  Future<void> _guess(String word) async {
    final input = TextEditingController();
    String? typed;
    await showWordlerDialog<void>(
      context,
      title: 'Guess the family word',
      body: TextField(
        controller: input,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: word.length,
        style: WText.button.copyWith(color: WColors.ink, letterSpacing: 2),
        decoration: const InputDecoration(hintText: 'Type the word'),
      ),
      actions: [
        WordlerDialogAction('Not yet', () {}, kind: ChunkyKind.secondary),
        WordlerDialogAction('Guess', () => typed = input.text),
      ],
    );
    final guess = typed;
    if (guess == null || guess.trim().isEmpty || !mounted) return;
    final right = ref.read(familyWordProvider.notifier).guess(
      text: guess,
      now: DateTime.now(),
      word: word,
      playerIds: [for (final p in ref.read(playersProvider).players) p.id],
    );
    if (right) {
      claimFamilyCoins(ref, context);
    } else {
      showWordlerDialog<void>(
        context,
        title: 'Not that one',
        bodyText: 'Good try! Finish more puzzles to find more letters, then guess again.',
        actions: [WordlerDialogAction('OK', () {})],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // In an online family, the family word is the online one (spec-09).
    if (ref.watch(familyOnlineProvider.select((s) => s.stage)) == OnlineStage.member) {
      return const OnlineFamilyWordScreen();
    }
    final players = ref.watch(playersProvider);
    ref.watch(familyWordProvider);
    ref.watch(dailyChallengeProvider);
    final now = DateTime.now();
    final data = ref.read(familyWordProvider.notifier).today(now);
    final words = ref.watch(wordsOfTheDayProvider).valueOrNull;
    if (words == null || words.isEmpty) {
      return const WordlerScaffold(title: "Today's family word", body: SizedBox.shrink());
    }
    final entry = familyWordFor(now, words);
    final word = entry.word;
    final mePlayed = ref.read(dailyChallengeProvider.notifier).hasPlayedToday(now);

    if (data.solved) return _Solved(entry: entry, data: data, players: players);

    final stillToPlay = players.players.where((p) => !data.found.containsKey(p.id)).length;
    return WordlerScaffold(
      title: "Today's family word",
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          ChunkyCard(
            color: WColors.skyTint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('THE HINT', style: WText.label.copyWith(color: WColors.ink)),
                const SizedBox(height: 4),
                Text(entry.meaning, style: WText.heading.copyWith(fontSize: 21)),
                const SizedBox(height: WSize.gap3),
                FamilyWordSlots(word: word, data: data, players: players, tileSize: 42),
                const SizedBox(height: WSize.gap2),
                Text(
                  '${data.revealed.length} of ${word.length} letters found. '
                  'The colored edge shows who found each one.',
                  style: WText.bodyBold.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                for (final p in players.players)
                  _MemberRow(
                    player: p,
                    isMe: p.id == players.currentId,
                    lettersFound: data.found[p.id]?.map((i) => word[i]).toList(),
                    playedToday: p.id == players.currentId ? mePlayed : (_summaries[p.id]?.playedToday ?? false),
                    onPass: p.id == players.currentId
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => PassPhoneScreen(player: p, summary: _summaries[p.id]),
                            )),
                  ),
              ],
            ),
          ),
          const SizedBox(height: WSize.gap3),
          Text(
            'Guess early and everyone gets +$kFamilyWordEarlyCoins coins. If all the letters come out first, '
            'everyone still gets +$kFamilyWordCoins.',
            style: WText.label,
          ),
          const SizedBox(height: WSize.gap3),
          if (!mePlayed)
            ChunkyButton(label: 'Play my puzzle', size: ChunkySize.big, expand: true, onPressed: _play)
          else
            Text(
              stillToPlay == 0 ? '' : 'You have played. Pass the phone on to find more letters.',
              style: WText.bodyBold,
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: WSize.gap2),
          ChunkyButton(
            label: 'We know it! Guess',
            kind: ChunkyKind.secondary,
            expand: true,
            onPressed: () => _guess(word),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.player,
    required this.isMe,
    required this.lettersFound,
    required this.playedToday,
    required this.onPass,
  });

  final Player player;
  final bool isMe;
  // Null = hasn't found letters today.
  final List<String>? lettersFound;
  final bool playedToday;
  final VoidCallback? onPass;

  @override
  Widget build(BuildContext context) {
    final found = lettersFound;
    final String status;
    if (found != null && found.isNotEmpty) {
      status = 'Found ${found.join(' and ')}';
    } else if (playedToday) {
      status = 'Played today';
    } else {
      status = isMe ? 'Your puzzle is ready' : 'Not played yet';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          PlayerAvatar(player: player),
          const SizedBox(width: WSize.gap2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isMe ? '${player.name} (you)' : player.name, style: WText.bodyBold),
                Text(status, style: WText.label),
              ],
            ),
          ),
          if (found != null || playedToday)
            const Icon(Icons.check_circle, color: WColors.grass, size: 28)
          else if (onPass != null)
            ChunkyButton(
              label: 'Pass to ${player.name}',
              kind: ChunkyKind.secondary,
              size: ChunkySize.small,
              onPressed: onPass,
            ),
        ],
      ),
    );
  }
}

class _Solved extends ConsumerWidget {
  const _Solved({required this.entry, required this.data, required this.players});

  final WordOfDay entry;
  final FamilyWordData data;
  final PlayersState players;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = data.solvedEarly ? kFamilyWordEarlyCoins : kFamilyWordCoins;
    return WordlerScaffold(
      title: 'Family word',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          ChunkyCard(
            hero: true,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  data.streak >= 2 ? 'Day ${data.streak} in a row' : 'Family word',
                  style: WText.label.copyWith(color: WColors.ink),
                ),
                const SizedBox(height: WSize.gap2),
                const Text('You found it together!', style: WText.heading, textAlign: TextAlign.center),
                const SizedBox(height: WSize.gap3),
                Center(child: FamilyWordSlots(word: entry.word, data: data, players: players, tileSize: 44)),
                const SizedBox(height: WSize.gap3),
                Text(entry.meaning, style: WText.body.copyWith(fontSize: 18), textAlign: TextAlign.center),
                const SizedBox(height: WSize.gap3),
                ChunkyButton(
                  label: 'Hear the word',
                  icon: Icons.volume_up,
                  kind: ChunkyKind.secondary,
                  expand: true,
                  onPressed: () => ref.read(wordSpeakerProvider).speak(entry.word),
                ),
                const SizedBox(height: WSize.gap3),
                Text('Everyone gets +$coins coins', style: WText.bodyBold.copyWith(color: WColors.grass)),
                const SizedBox(height: WSize.gap2),
                Wrap(
                  spacing: 8,
                  children: [for (final p in players.players) PlayerAvatar(player: p, size: 40)],
                ),
              ],
            ),
          ),
          const SizedBox(height: WSize.gap3),
          const Text('Come back tomorrow for a new family word.', style: WText.label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Everyone on this phone, with their level and progress. Reached from
/// Home's Family button, and from Settings when there is only one player.
class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  Map<String, PlayerSummary> _summaries = const {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final summaries = await loadSummaries(ref.read(playersProvider).players, DateTime.now());
    if (mounted) setState(() => _summaries = summaries);
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<Object?>(builder: (_) => screen));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playersProvider);
    final family = ref.watch(familyWordProvider);
    return WordlerScaffold(
      title: players.isFamily ? 'The family' : 'Players on this phone',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          if (players.isFamily) ...[
            ChunkyCard(
              color: WColors.sunTint,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Family words found', style: WText.heading.copyWith(fontSize: 20)),
                        Text(
                          family.total == 0
                              ? 'None yet. Today could be the first.'
                              : '${family.streak} day${family.streak == 1 ? '' : 's'} in a row · ${family.total} in all',
                          style: WText.bodyBold.copyWith(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  Text('${family.total}', style: WText.number),
                ],
              ),
            ),
            const SizedBox(height: WSize.gap3),
          ] else ...[
            const Text(
              'Add the people you share this phone with. Each one gets their own village, coins and puzzles, '
              'and you all work on a family word together.',
              style: WText.body,
            ),
            const SizedBox(height: WSize.gap3),
          ],
          for (final p in players.players)
            Padding(
              padding: const EdgeInsets.only(bottom: WSize.gap3),
              child: _FamilyRow(
                player: p,
                summary: _summaries[p.id],
                isMe: p.id == players.currentId,
                onEdit: () => _push(AddPlayerScreen(editing: p)),
                onVisit: p.id == players.currentId ? null : () => _push(VisitVillageScreen(player: p)),
              ),
            ),
          if (players.isFamily)
            const Text(
              "Visit shows someone's village. You can look around, but only they can build there.",
              style: WText.label,
            ),
          const SizedBox(height: WSize.gap3),
          if (players.canAdd)
            ChunkyButton(
              label: 'Add a player',
              kind: ChunkyKind.secondary,
              expand: true,
              onPressed: () => _push(const AddPlayerScreen()),
            ),
          const SizedBox(height: WSize.gap4),
          const FamilyOnlineRow(),
        ],
      ),
    );
  }
}

class _FamilyRow extends StatelessWidget {
  const _FamilyRow({
    required this.player,
    required this.summary,
    required this.isMe,
    required this.onEdit,
    required this.onVisit,
  });

  final Player player;
  final PlayerSummary? summary;
  final bool isMe;
  final VoidCallback onEdit;
  final VoidCallback? onVisit;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          PlayerAvatar(player: player, size: 48),
          const SizedBox(width: WSize.gap3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isMe ? '${player.name} (you)' : player.name, style: WText.heading.copyWith(fontSize: 20)),
                if (summary != null) ...[
                  Text(summary.level.info.name, style: WText.bodyBold.copyWith(fontSize: 15)),
                  Text('Journal ${summary.journal}/${kMagicWords.length}', style: WText.label),
                ],
              ],
            ),
          ),
          ChunkyIconButton(icon: Icons.edit, tooltip: 'Change ${player.name}', onPressed: onEdit),
          if (onVisit != null) ...[
            const SizedBox(width: WSize.gap2),
            ChunkyButton(label: 'Visit', kind: ChunkyKind.secondary, size: ChunkySize.small, onPressed: onVisit),
          ],
        ],
      ),
    );
  }
}

/// Another player's village, to look at (spec-22 C): their streets on the
/// planet, close up. Pan and zoom, tap a building or word for its card;
/// nothing can be moved or built.
class VisitVillageScreen extends ConsumerStatefulWidget {
  const VisitVillageScreen({super.key, required this.player});

  final Player player;

  @override
  ConsumerState<VisitVillageScreen> createState() => _VisitVillageScreenState();
}

class _VisitVillageScreenState extends ConsumerState<VisitVillageScreen> {
  PlanetData? _planet;
  int? _focus;
  bool _loaded = false;
  List<BoardStructure> _structures = const [];
  List<WordRun> _words = const [];
  Map<String, SpriteMeta> _meta = const {};
  Set<int> _highlight = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Only the cards' pictures: the planet doesn't wait for them.
    VillageArt.loadMeta().then((meta) => _meta = meta, onError: (_) {});
    final raw = await VillageSaveController(prefix: widget.player.prefix).load();
    PlanetData? planet;
    int? focus;
    if (raw != null && raw.boardCells.any((c) => c != null)) {
      // Only read: the save is laid on the planet the way the village does,
      // and nothing is written back.
      final saved =
          migrateVillageSave(raw, rackSize: InfiniteEstateScreen.rackSize, planetSlot: raw.planetSlot ?? 0);
      const size = InfiniteEstateScreen.boardSize;
      final board = saved.starActive
          ? null
          : await settle(saved.boardCells, size, size, ref.read(wordCheckProvider), kept: saved.keptRuns);
      _structures = computeStructures(board?.settledRuns ?? const []);
      _words = board?.settledRuns ?? const [];
      final letters = {
        for (var i = 0; i < saved.boardCells.length; i++)
          if (saved.boardCells[i] != null) i: saved.boardCells[i]!,
      };
      planet = PlanetData.of(PlanetVillage(
        player: widget.player,
        slot: saved.planetSlot ?? 0,
        letters: letters,
        runs: [for (final b in _structures) (word: b.def.word, cells: b.ordered)],
        fog: saved.cleared == null ? null : FogMap.fromBase64(saved.cleared!),
        loose: board?.looseCells ?? letters.keys.toSet(),
      ));
      focus = _structures.isNotEmpty ? _structures.last.middle : _middleLetter(letters.keys);
    }
    if (mounted) {
      setState(() {
        _planet = planet;
        _focus = focus;
        _loaded = true;
      });
    }
  }

  // The letter nearest the middle of all of them.
  static int _middleLetter(Iterable<int> cells) {
    final list = cells.toList();
    final r = list.fold<double>(0, (t, i) => t + i ~/ kPlanetBoard) / list.length;
    final c = list.fold<double>(0, (t, i) => t + i % kPlanetBoard) / list.length;
    double d(int i) => math.pow(i ~/ kPlanetBoard - r, 2) + math.pow(i % kPlanetBoard - c, 2).toDouble();
    return list.reduce((a, b) => d(a) <= d(b) ? a : b);
  }

  Future<String?> _meaning(String word) => ref.read(definitionServiceProvider).getDefinition(word);

  Future<void> _tap(Offset at, GlobeProjection proj, PlanetData data) async {
    final hit = streetHit(at, proj, data.villages.first);
    switch (hit) {
      case StreetBuilding(:final run) when run < _structures.length:
        final structure = _structures[run];
        setState(() => _highlight = structure.positions);
        await showVillageSheet<void>(
          context,
          BuildingCard(
            def: structure.def,
            cardImagePath: _meta[structure.def.word]?.cardPath,
            loadDefinition: _meaning,
          ),
        );
      case StreetLetter(:final cell):
        final runs = _words.where((r) => r.positions.contains(cell)).toList()
          ..sort((a, b) => (a.across ? 0 : 1).compareTo(b.across ? 0 : 1));
        if (runs.isEmpty) return; // a loose letter: nothing to say about it here
        setState(() => _highlight = runs.first.positions.toSet());
        await showVillageSheet<void>(
          context,
          WordCard(
            runs: runs,
            loadDefinition: _meaning,
            onWordChanged: (run) => setState(() => _highlight = run.positions.toSet()),
          ),
        );
      default:
        return;
    }
    if (mounted) setState(() => _highlight = const {});
  }

  @override
  Widget build(BuildContext context) {
    final data = _planet;
    if (!_loaded || data == null) {
      return WordlerScaffold(
        title: "${widget.player.name}'s village",
        body: !_loaded
            ? const SizedBox.shrink()
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(WSize.screenPadding),
                  child: Text(
                    "${widget.player.name} hasn't built anything yet.",
                    style: WText.body,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
      );
    }
    final reduce = ref.watch(settingsProvider.select((st) => st.reduceMotion));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        backgroundColor: kGlobeSky,
        body: GlobeView(
          villages: data.villages,
          takenSlots: data.takenSlots,
          focusSlot: data.mySlot,
          isHushed: data.isHushed,
          reduceMotion: reduce,
          alwaysPan: true,
          closeUp: true,
          initialCell: _focus,
          initialZoom: kStreetZoom,
          highlight: _highlight,
          zoomButtonsBottomFor: (_) => MediaQuery.paddingOf(context).bottom + 24,
          onStreetTap: (at, proj) => _tap(at, proj, data),
          overlay: (proj, cell) => [
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(WSize.screenPadding),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Row(children: [
                      ChunkyIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          "${widget.player.name}'s village",
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WText.heading.copyWith(fontSize: 26, color: WColors.ink),
                        ),
                      ),
                      const SizedBox(width: WSize.tapTarget),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
