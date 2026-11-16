import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily/daily_seed.dart' show dailyDateKey;
import '../game/letter_tile.dart';
import '../online/family_online_controller.dart';
import '../online/family_online_models.dart';
import '../online/firebase_family_backend.dart' show RecentSignInNeeded;
import '../players/player_summary.dart';
import '../players/players.dart';
import '../settings/settings_controller.dart';
import '../settings/word_level.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import '../ui/wordler_scaffold.dart';
import 'family_word_online_screens.dart' show FamilyMapScreen;

// Family online (spec-08): sign in, start or join a family with a code,
// a grown-up's yes for every new member, and the account page. Reached from
// Settings > Family online and from the family page.

/// The player holding the phone, as the family will see them.
MemberInfo currentMemberInfo(WidgetRef ref) {
  final player = ref.read(playersProvider).current;
  return MemberInfo(
    name: player.name,
    colorIndex: player.colorIndex,
    level: ref.read(settingsProvider).wordLevel,
  );
}

Player _asPlayer(String id, String name, int colorIndex) => Player(id: id, name: name, colorIndex: colorIndex);

/// Runs a call to the server, with a gentle message if it fails.
Future<bool> _tryOnline(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't reach the family just now. Check the internet and try again.")),
      );
    }
    return false;
  }
}

String _namesList(List<String> names) {
  if (names.isEmpty) return 'a grown-up';
  if (names.length == 1) return names.first;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// One screen that shows whatever fits where this player stands: the
/// introduction, waiting for a yes, or their family and account.
class FamilyOnlineScreen extends ConsumerWidget {
  const FamilyOnlineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    return switch (online.stage) {
      OnlineStage.loading => const WordlerScaffold(
          title: 'Family online',
          body: Center(child: CircularProgressIndicator()),
        ),
      OnlineStage.unavailable => const WordlerScaffold(
          title: 'Family online',
          body: Padding(
            padding: EdgeInsets.all(WSize.screenPadding),
            child: Text(
              "Family online isn't switched on in this copy of the app yet. "
              'Everything on this phone works as before.',
              style: WText.body,
            ),
          ),
        ),
      OnlineStage.signedOut || OnlineStage.noFamily => const _IntroView(),
      OnlineStage.waiting => const _WaitingView(),
      OnlineStage.member => const AccountView(),
    };
  }
}

// ---- 81: Family online ---------------------------------------------------------

class _IntroView extends ConsumerWidget {
  const _IntroView();

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    if (ref.read(familyOnlineProvider).account == null) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
      if (ok != true || !context.mounted) return;
    }
    if (!ref.read(familyOnlineProvider).isAdult) {
      await showWordlerDialog<void>(
        context,
        title: 'A grown-up starts the family',
        bodyText: 'Ask a grown-up in your family to start it. They will give you a code to join with.',
        actions: [WordlerDialogAction('OK', () {})],
      );
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const FamilyCodeScreen()));
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    if (ref.read(familyOnlineProvider).account == null) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
      if (ok != true || !context.mounted) return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const JoinFamilyScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    final players = ref.watch(playersProvider).players;
    return WordlerScaffold(
      title: 'Family online',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(WSize.screenPadding),
              children: [
                if (online.declined) ...[
                  ChunkyCard(
                    color: WColors.coralTint,
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Not this time: the family said not now. You can ask again with a code.',
                              style: WText.bodyBold),
                        ),
                        ChunkyIconButton(
                          icon: Icons.close,
                          tooltip: 'OK',
                          onPressed: () => ref.read(familyOnlineProvider.notifier).clearDeclined(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: WSize.gap3),
                ],
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    for (final p in players.take(4)) PlayerAvatar(player: p, size: 48),
                    if (players.length < 2)
                      for (final c in [1, 2, 3]) PlayerAvatar(player: _asPlayer('x$c', '?', c), size: 48),
                  ],
                ),
                const SizedBox(height: WSize.gap3),
                Semantics(
                  header: true,
                  child: Text('Play together, even on different phones',
                      textAlign: TextAlign.center, style: WText.heading.copyWith(fontSize: 26)),
                ),
                const SizedBox(height: WSize.gap3),
                const ChunkyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SHARED WITH YOUR FAMILY', style: WText.label),
                      SizedBox(height: WSize.gap2),
                      _Tick('Your first name and color'),
                      _Tick('Your word level'),
                      _Tick('Whether you have played today'),
                      _Tick('Your buildings, and how many of each'),
                      _Tick('The family-word letters you uncover, and a right guess'),
                      _Tick('Letters you give or ask for'),
                      _Tick('Cheers you send: a sticker and your name'),
                      SizedBox(height: WSize.gap3),
                      Text('STAYS ON THIS PHONE', style: WText.label),
                      SizedBox(height: WSize.gap2),
                      _Tick("Your village's words and letters", shared: false),
                      _Tick('Your coins, puzzles and clues', shared: false),
                      _Tick('Wrong guesses', shared: false),
                      SizedBox(height: WSize.gap3),
                      Text('NEVER', style: WText.label),
                      SizedBox(height: WSize.gap2),
                      _Tick('Typed messages: there is no chat', shared: false),
                      _Tick('Anything to or from people outside the family', shared: false),
                    ],
                  ),
                ),
                const SizedBox(height: WSize.gap3),
                const Text(
                  'Everyone signs in. A grown-up already in the family says yes to each new member, '
                  'and children under 13 never give an email.',
                  style: WText.label,
                ),
                if (online.account != null) ...[
                  const SizedBox(height: WSize.gap3),
                  TextButton(
                    onPressed: () => ref.read(familyOnlineProvider.notifier).signOut(),
                    child: Text('Signed in. Sign out', style: WText.bodyBold.copyWith(color: WColors.grass)),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 0, WSize.screenPadding, WSize.screenPadding),
              child: Column(
                children: [
                  ChunkyButton(label: 'Start a family', expand: true, onPressed: () => _start(context, ref)),
                  const SizedBox(height: WSize.gap3),
                  ChunkyButton(
                    label: 'Join with a code',
                    kind: ChunkyKind.secondary,
                    expand: true,
                    onPressed: () => _join(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick(this.text, {this.shared = true});

  final String text;
  final bool shared;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: shared ? WColors.leaf : WColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
            ),
            child: Icon(shared ? Icons.check : Icons.phone_android, size: 15, color: WColors.ink),
          ),
          const SizedBox(width: WSize.gap2),
          Expanded(child: Text(text, style: WText.body)),
        ],
      ),
    );
  }
}

// ---- 82: Sign in ----------------------------------------------------------------

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Asks the birth month and year first, then signs in the way that fits:
/// Google or an emailed link for 13 and over, no email at all under 13.
/// Pops true once signed in.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.now});

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  int? _month;
  int? _year;
  final _email = TextEditingController();
  bool _busy = false;

  DateTime get _now => widget.now ?? DateTime.now();

  AgeGroup? get _group {
    final m = _month;
    final y = _year;
    if (m == null || y == null) return null;
    return ageGroupFor(birthYear: y, birthMonth: m, now: _now);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _busy = true);
    var done = false;
    await _tryOnline(context, () async => done = await action());
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) Navigator.of(context).pop(true);
  }

  Widget _picker<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) text,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: WColors.white,
        borderRadius: BorderRadius.circular(WSize.radiusButton),
        border: Border.all(color: WColors.ink, width: WSize.outline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          hint: Text(label, style: WText.bodyBold.copyWith(color: WColors.muted)),
          style: WText.bodyBold,
          dropdownColor: WColors.card,
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text(text(i)))],
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(familyOnlineProvider);
    // An emailed link finished signing in while this screen was open.
    ref.listen(familyOnlineProvider.select((s) => s.account), (before, after) {
      if (before == null && after != null && mounted) Navigator.of(context).pop(true);
    });
    final controller = ref.read(familyOnlineProvider.notifier);
    final group = _group;
    final year = _year;
    final email = _email.text.trim();
    final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    return WordlerScaffold(
      title: 'Sign in',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          ChunkyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('WHEN WERE YOU BORN?', style: WText.label),
                const SizedBox(height: WSize.gap2),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _picker<int>(
                        label: 'Month',
                        value: _month,
                        items: List.generate(12, (i) => i + 1),
                        text: (m) => _months[m - 1],
                        onChanged: (m) => setState(() => _month = m),
                      ),
                    ),
                    const SizedBox(width: WSize.gap2),
                    Expanded(
                      flex: 2,
                      child: _picker<int>(
                        label: 'Year',
                        value: _year,
                        items: List.generate(100, (i) => _now.year - i),
                        text: (y) => '$y',
                        onChanged: (y) => setState(() => _year = y),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WSize.gap2),
                Text(
                  'This tells us whether a grown-up needs to say yes. We keep only the year.',
                  style: WText.label.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: WSize.gap4),
          if (group == AgeGroup.child && year != null) ...[
            const Text(
              "You don't need an email. Next, type your family's code, and a grown-up in the family says yes.",
              style: WText.body,
            ),
            const SizedBox(height: WSize.gap3),
            ChunkyButton(
              label: 'Next',
              expand: true,
              onPressed: _busy ? null : () => _run(() async {
                    await controller.signInAsChild(birthYear: year);
                    return true;
                  }),
            ),
          ] else if (group != null && year != null) ...[
            ChunkyButton(
              label: 'Continue with Google',
              icon: Icons.account_circle,
              kind: ChunkyKind.secondary,
              expand: true,
              onPressed: _busy
                  ? null
                  : () => _run(() => controller.signInWithGoogle(birthYear: year, group: group)),
            ),
            const SizedBox(height: WSize.gap4),
            const Row(
              children: [
                Expanded(child: Divider(color: WColors.boardBed, thickness: 3)),
                Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: WText.label)),
                Expanded(child: Divider(color: WColors.boardBed, thickness: 3)),
              ],
            ),
            const SizedBox(height: WSize.gap3),
            const Text('EMAIL', style: WText.label),
            const SizedBox(height: 4),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: WText.bodyBold,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'you@example.com',
                filled: true,
                fillColor: WColors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(WSize.radiusButton),
                  borderSide: const BorderSide(color: WColors.ink, width: WSize.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(WSize.radiusButton),
                  borderSide: const BorderSide(color: WColors.grass, width: WSize.outline + 1),
                ),
              ),
            ),
            const SizedBox(height: WSize.gap3),
            ChunkyButton(
              label: 'Email me a sign-in link',
              kind: ChunkyKind.secondary,
              expand: true,
              onPressed: _busy || !emailOk
                  ? null
                  : () => _tryOnline(context, () => controller.sendEmailLink(email, birthYear: year, group: group)),
            ),
            const SizedBox(height: WSize.gap2),
            if (online.emailSentTo != null)
              ChunkyCard(
                color: WColors.leafTint,
                child: Text(
                  'Sent! Open the email to ${online.emailSentTo} on this phone and tap the link.',
                  style: WText.bodyBold,
                ),
              )
            else
              const Text(
                "No password to remember: tap the link in the email and you're in. "
                'Your email is never shown to the family.',
                style: WText.label,
              ),
          ],
          if (_busy) ...[
            const SizedBox(height: WSize.gap4),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}

// ---- 83: Your family code ---------------------------------------------------------

/// The code as letter tiles: BEAR on one row, 4821 on the next.
class FamilyCodeTiles extends StatelessWidget {
  const FamilyCodeTiles({super.key, required this.code, this.size = 52});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget row(String part) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in part.split(''))
              Padding(
                padding: const EdgeInsets.all(3),
                child: SizedBox(width: size, height: size, child: LetterTile(letter: c)),
              ),
          ],
        );
    return Semantics(
      label: 'Family code ${code.split('').join(' ')}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(code.length >= 4 ? code.substring(0, 4) : code),
          if (code.length > 4) row(code.substring(4)),
        ],
      ),
    );
  }
}

/// Starts a family: its name, then its code to read out or send.
class FamilyCodeScreen extends ConsumerStatefulWidget {
  const FamilyCodeScreen({super.key});

  @override
  ConsumerState<FamilyCodeScreen> createState() => _FamilyCodeScreenState();
}

class _FamilyCodeScreenState extends ConsumerState<FamilyCodeScreen> {
  late final TextEditingController _name = TextEditingController(text: 'Our family');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    await _tryOnline(
      context,
      () => ref.read(familyOnlineProvider.notifier).createFamily(name: name, me: currentMemberInfo(ref)),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final family = ref.watch(familyOnlineProvider).family;
    return WordlerScaffold(
      title: 'Your family',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(WSize.screenPadding),
              children: [
                if (family == null) ...[
                  const Text('FAMILY NAME', style: WText.label),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _name,
                    maxLength: 24,
                    textCapitalization: TextCapitalization.words,
                    style: WText.bodyBold.copyWith(fontSize: 20),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: WColors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(WSize.radiusButton),
                        borderSide: const BorderSide(color: WColors.ink, width: WSize.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(WSize.radiusButton),
                        borderSide: const BorderSide(color: WColors.grass, width: WSize.outline + 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: WSize.gap2),
                  const Text('Like "The Rivera family". Everyone in it sees this name.', style: WText.label),
                ] else ...[
                  Text(family.name, style: WText.heading, textAlign: TextAlign.center),
                  const SizedBox(height: WSize.gap3),
                  ChunkyCard(
                    child: Column(
                      children: [
                        const Text('FAMILY CODE', style: WText.label),
                        const SizedBox(height: WSize.gap2),
                        FamilyCodeTiles(code: family.code),
                        const SizedBox(height: WSize.gap2),
                        const Text('Read it out, or send it to your family.',
                            style: WText.label, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  const SizedBox(height: WSize.gap3),
                  SendCodeButton(family: family),
                  const SizedBox(height: WSize.gap3),
                  const Text(
                    'Anyone with the code can ask to join, and a grown-up in the family says yes or not now. '
                    'You can change the code any time.',
                    style: WText.label,
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 0, WSize.screenPadding, WSize.screenPadding),
              child: family == null
                  ? ChunkyButton(
                      label: 'Make our family code',
                      size: ChunkySize.big,
                      expand: true,
                      onPressed: _busy || _name.text.trim().isEmpty ? null : _create,
                    )
                  : ChunkyButton(
                      label: 'Done',
                      size: ChunkySize.big,
                      expand: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Copies a short invitation with the code, ready to paste into a message.
class SendCodeButton extends StatelessWidget {
  const SendCodeButton({super.key, required this.family});

  final OnlineFamily family;

  @override
  Widget build(BuildContext context) {
    return ChunkyButton(
      label: 'Copy the code to send',
      icon: Icons.copy,
      kind: ChunkyKind.secondary,
      expand: true,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(
          text: 'Join ${family.name} on Mr. Wordler! Open Settings > Family online, '
              'tap Join with a code, and type ${showFamilyCode(family.code)}.',
        ));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copied. Paste it into a message to your family.')),
          );
        }
      },
    );
  }
}

// ---- 84: Join with a code ------------------------------------------------------------

class JoinFamilyScreen extends ConsumerStatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  ConsumerState<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends ConsumerState<JoinFamilyScreen> {
  final _code = TextEditingController();
  FamilyPreview? _found;
  String? _foundCode;
  bool _notFound = false;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final code = normalizeFamilyCode(_code.text);
    if (code == null) return;
    setState(() {
      _busy = true;
      _notFound = false;
    });
    FamilyPreview? found;
    await _tryOnline(context, () async => found = await ref.read(familyOnlineProvider.notifier).findFamily(code));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _found = found;
      _foundCode = found == null ? null : code;
      _notFound = found == null;
    });
  }

  Future<void> _ask() async {
    final found = _found;
    final code = _foundCode;
    if (found == null || code == null) return;
    setState(() => _busy = true);
    final ok = await _tryOnline(
      context,
      () => ref.read(familyOnlineProvider.notifier).requestToJoin(family: found, code: code, me: currentMemberInfo(ref)),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final player = ref.watch(playersProvider).current;
    final level = ref.watch(settingsProvider).wordLevel;
    final codeOk = normalizeFamilyCode(_code.text) != null;
    return WordlerScaffold(
      title: 'Join a family',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(WSize.screenPadding),
              children: [
                const Text('Type the code your family gave you.', style: WText.body),
                const SizedBox(height: WSize.gap2),
                TextField(
                  controller: _code,
                  maxLength: 9,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: WFonts.display, fontSize: 30, letterSpacing: 4, color: WColors.ink),
                  onChanged: (_) => setState(() {
                    _found = null;
                    _notFound = false;
                  }),
                  onSubmitted: (_) => _find(),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'BEAR 4821',
                    filled: true,
                    fillColor: WColors.white,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(WSize.radiusButton),
                      borderSide: const BorderSide(color: WColors.ink, width: WSize.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(WSize.radiusButton),
                      borderSide: const BorderSide(color: WColors.grass, width: WSize.outline + 1),
                    ),
                  ),
                ),
                const SizedBox(height: WSize.gap3),
                if (found == null)
                  ChunkyButton(
                    label: 'Find the family',
                    kind: ChunkyKind.secondary,
                    expand: true,
                    onPressed: _busy || !codeOk ? null : _find,
                  ),
                if (_notFound) ...[
                  const SizedBox(height: WSize.gap3),
                  const Text("No family has that code. Check it with whoever sent it; they can make a new one.",
                      style: WText.bodyBold),
                ],
                if (found != null) ...[
                  ChunkyCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('FOUND IT', style: WText.label),
                        Text(found.name, style: WText.heading.copyWith(fontSize: 22)),
                        if (found.adultNames.isNotEmpty)
                          Text('With ${_namesList(found.adultNames)}', style: WText.bodyBold.copyWith(fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: WSize.gap3),
                  ChunkyCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("YOU'LL JOIN AS", style: WText.label),
                        const SizedBox(height: WSize.gap2),
                        Row(
                          children: [
                            PlayerAvatar(player: player, size: 48),
                            const SizedBox(width: WSize.gap3),
                            Expanded(child: Text(player.name, style: WText.heading.copyWith(fontSize: 20))),
                            Text(level.info.name, style: WText.bodyBold.copyWith(fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: WSize.gap2),
                        const Text('Your village and coins stay yours, on this phone.', style: WText.label),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (found != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 0, WSize.screenPadding, WSize.screenPadding),
                child: ChunkyButton(
                  label: 'Ask to join',
                  size: ChunkySize.big,
                  expand: true,
                  onPressed: _busy ? null : _ask,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- 85: Waiting for a yes ---------------------------------------------------------------

class _WaitingView extends ConsumerWidget {
  const _WaitingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    final player = ref.watch(playersProvider).current;
    final waiting = online.waitingFor;
    final names = _namesList(waiting?.adultNames ?? const []);
    final child = online.group == AgeGroup.child;
    final isFamilyPhone = ref.watch(playersProvider).isFamily;
    return WordlerScaffold(
      title: 'Almost there!',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(WSize.screenPadding),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PlayerAvatar(player: player, size: 60),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.arrow_forward, size: 32, color: WColors.muted),
                    ),
                    const Icon(Icons.groups, size: 56, color: WColors.ink),
                  ],
                ),
                const SizedBox(height: WSize.gap4),
                Semantics(
                  header: true,
                  child: Text(
                    child ? 'Ask a grown-up to say yes' : 'Waiting for a yes',
                    textAlign: TextAlign.center,
                    style: WText.heading,
                  ),
                ),
                const SizedBox(height: WSize.gap3),
                Text(
                  '${player.name}, a grown-up in ${waiting?.name ?? 'the family'} needs to say yes '
                  'before you can play together online.',
                  textAlign: TextAlign.center,
                  style: WText.body,
                ),
                const SizedBox(height: WSize.gap4),
                ChunkyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1. We asked $names on their phone.', style: WText.body),
                      const SizedBox(height: WSize.gap2),
                      const Text('2. When they say yes, this page changes by itself.', style: WText.body),
                    ],
                  ),
                ),
                if (isFamilyPhone) ...[
                  const SizedBox(height: WSize.gap3),
                  const Text(
                    'If that grown-up shares this phone, switch to them and open Family online: '
                    'they can say yes from there.',
                    style: WText.label,
                  ),
                ],
                const SizedBox(height: WSize.gap4),
                TextButton(
                  onPressed: () => _tryOnline(context, () => ref.read(familyOnlineProvider.notifier).cancelRequest()),
                  child: Text('Stop asking', style: WText.bodyBold.copyWith(color: WColors.brick)),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 0, WSize.screenPadding, WSize.screenPadding),
              child: ChunkyButton(
                label: 'Play while I wait',
                size: ChunkySize.big,
                expand: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 86 + 87: A grown-up says yes; Account and family ---------------------------------------

class AccountView extends ConsumerStatefulWidget {
  const AccountView({super.key, this.now});

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends ConsumerState<AccountView> {
  @override
  void initState() {
    super.initState();
    // Bring the family's copy of this player up to date with the phone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(familyOnlineProvider.notifier).syncMe(currentMemberInfo(ref));
    });
  }

  Future<void> _confirm({
    required String title,
    required String body,
    required String yes,
    required Future<void> Function() action,
  }) async {
    var go = false;
    await showWordlerDialog<void>(
      context,
      title: title,
      bodyText: body,
      actions: [
        WordlerDialogAction(yes, () => go = true, kind: ChunkyKind.danger),
        WordlerDialogAction('Keep it', () {}, kind: ChunkyKind.secondary),
      ],
    );
    if (go && mounted) await _tryOnline(context, action);
  }

  Future<void> _delete() async {
    var go = false;
    await showWordlerDialog<void>(
      context,
      title: 'Delete your account?',
      bodyText: 'You leave the family and everything about you is removed from the family online. '
          'Your village and coins stay on this phone.',
      actions: [
        WordlerDialogAction('Delete my account', () => go = true, kind: ChunkyKind.danger),
        WordlerDialogAction('Keep it', () {}, kind: ChunkyKind.secondary),
      ],
    );
    if (!go || !mounted) return;
    try {
      await ref.read(familyOnlineProvider.notifier).deleteAccount();
    } on RecentSignInNeeded {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('For safety, sign out and sign in again, then delete.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't reach the family just now. Check the internet and try again."),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(familyOnlineProvider);
    final controller = ref.read(familyOnlineProvider.notifier);
    final family = online.family;
    final me = online.me;
    final account = online.account;
    final today = dailyDateKey(widget.now ?? DateTime.now());
    if (family == null || me == null || account == null) {
      return const WordlerScaffold(title: 'Account', body: Center(child: CircularProgressIndicator()));
    }
    final signedInWith = switch (account.method) {
      SignInMethod.google => 'with Google',
      SignInMethod.email => 'with an email link',
      SignInMethod.child => 'with a grown-up\'s yes',
    };
    final masked = account.maskedEmail;
    return WordlerScaffold(
      title: 'Account',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          if (me.adult)
            for (final r in family.requests) ...[
              ApproveCard(
                request: r,
                now: widget.now ?? DateTime.now(),
                onYes: () => _tryOnline(context, () => controller.approve(r)),
                onNo: () => _tryOnline(context, () => controller.decline(r)),
              ),
              const SizedBox(height: WSize.gap3),
            ],
          ChunkyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SIGNED IN', style: WText.label),
                const SizedBox(height: WSize.gap2),
                Row(
                  children: [
                    PlayerAvatar(player: _asPlayer(me.uid, me.name, me.colorIndex), size: 48),
                    const SizedBox(width: WSize.gap3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(me.name, style: WText.heading.copyWith(fontSize: 20)),
                          Text([signedInWith, if (masked != null) masked].join(' · '),
                              style: WText.label.copyWith(fontSize: 15)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(family.name, style: WText.heading.copyWith(fontSize: 20))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: WColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                      ),
                      child: Text(showFamilyCode(family.code), style: WText.buttonSmall.copyWith(color: WColors.ink)),
                    ),
                  ],
                ),
                const SizedBox(height: WSize.gap3),
                for (final m in family.members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: WSize.gap2),
                    child: Row(
                      children: [
                        PlayerAvatar(player: _asPlayer(m.uid, m.name, m.colorIndex), size: 40),
                        const SizedBox(width: WSize.gap3),
                        Expanded(
                          child: Text(m.uid == me.uid ? '${m.name} (you)' : m.name, style: WText.bodyBold),
                        ),
                        _PlayedPill(played: m.playedOn(today)),
                        if (me.adult && m.uid != me.uid)
                          IconButton(
                            tooltip: 'Remove ${m.name}',
                            icon: const Icon(Icons.more_vert, color: WColors.ink),
                            onPressed: () => _confirm(
                              title: 'Remove ${m.name}?',
                              body: '${m.name} leaves the family online. Their village stays on their phone, '
                                  'and they can ask to join again with the code.',
                              yes: 'Remove ${m.name}',
                              action: () => controller.removeMember(m.uid),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyButton(
            label: 'The family map',
            expand: true,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FamilyMapScreen())),
          ),
          const SizedBox(height: WSize.gap3),
          SendCodeButton(family: family),
          if (me.adult) ...[
            const SizedBox(height: WSize.gap3),
            ChunkyButton(
              label: 'New family code',
              kind: ChunkyKind.secondary,
              expand: true,
              onPressed: () => _confirm(
                title: 'Make a new code?',
                body: 'The old code stops working. Everyone already in the family stays in.',
                yes: 'New code',
                action: () async => controller.newCode(),
              ),
            ),
          ],
          const SizedBox(height: WSize.gap5),
          ChunkyButton(
            label: 'Leave the family',
            kind: ChunkyKind.secondary,
            expand: true,
            onPressed: () => _confirm(
              title: 'Leave ${family.name}?',
              body: 'The family stops seeing you. Your village and coins stay on this phone.',
              yes: 'Leave',
              action: controller.leave,
            ),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyButton(label: 'Delete my account', kind: ChunkyKind.danger, expand: true, onPressed: _delete),
          const SizedBox(height: WSize.gap3),
          Center(
            child: TextButton(
              onPressed: controller.signOut,
              child: Text('Sign out', style: WText.bodyBold.copyWith(color: WColors.grass)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayedPill extends StatelessWidget {
  const _PlayedPill({required this.played});

  final bool played;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: played ? WColors.leaf : WColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
      ),
      child: Text(played ? 'Played' : 'Not yet', style: WText.buttonSmall.copyWith(color: WColors.ink, fontSize: 15)),
    );
  }
}

/// Someone asking to join, as a grown-up in the family sees it.
class ApproveCard extends StatelessWidget {
  const ApproveCard({super.key, required this.request, required this.now, required this.onYes, required this.onNo});

  final JoinRequest request;
  final DateTime now;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final age = switch (r.group) {
      AgeGroup.child => 'Under 13',
      AgeGroup.teen => '13 to 17',
      AgeGroup.adult => 'Grown-up',
    };
    return ChunkyCard(
      color: WColors.sunTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PlayerAvatar(player: _asPlayer(r.uid, r.name, r.colorIndex), size: 48),
              const SizedBox(width: WSize.gap3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.name} wants to join', style: WText.heading.copyWith(fontSize: 20)),
                    Text('Born ${r.birthYear} · $age · ${r.level.info.name}', style: WText.label.copyWith(fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: WSize.gap3),
          Text('If you say yes, the family will see:', style: WText.body.copyWith(fontSize: 16)),
          const SizedBox(height: WSize.gap2),
          _Tick("${r.name}'s first name, color and level"),
          _Tick('Whether ${r.name} has played today'),
          _Tick("${r.name}'s buildings and family-word letters"),
          _Tick('Letters and cheer stickers ${r.name} sends or asks for'),
          if (r.group == AgeGroup.adult) const _Tick('They can say yes to new members too'),
          const SizedBox(height: WSize.gap2),
          Text(
            'There is no chat, and nobody outside the family can find ${r.name}. '
            'You can remove them at any time.',
            style: WText.label.copyWith(fontSize: 15),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyButton(label: 'Yes, ${r.name} can join', expand: true, onPressed: onYes),
          const SizedBox(height: WSize.gap2),
          ChunkyButton(label: 'Not now', kind: ChunkyKind.secondary, expand: true, onPressed: onNo),
        ],
      ),
    );
  }
}

/// The Settings / family page row: how family online stands at a glance.
class FamilyOnlineRow extends ConsumerWidget {
  const FamilyOnlineRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    final requests = online.family?.requests.length ?? 0;
    final subtitle = switch (online.stage) {
      OnlineStage.member when requests > 0 =>
        '$requests asking to join ${online.family?.name ?? ''}'.trim(),
      OnlineStage.member => online.family?.name ?? 'In a family',
      OnlineStage.waiting => 'Waiting for a yes',
      OnlineStage.unavailable => 'Coming soon',
      _ => 'Play together on different phones',
    };
    return ChunkyCard(
      color: requests > 0 ? WColors.sunTint : WColors.card,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FamilyOnlineScreen())),
      child: Row(
        children: [
          const Icon(Icons.cloud_outlined, color: WColors.ink, size: 28),
          const SizedBox(width: WSize.gap3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Family online', style: WText.heading.copyWith(fontSize: 22)),
                Text(subtitle, style: WText.body.copyWith(color: WColors.muted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: WColors.ink),
        ],
      ),
    );
  }
}
