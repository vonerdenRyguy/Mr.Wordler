# Mr. Wordler

A Bananagrams-style word tile game (Flutter/Dart). Draw letter tiles from a
pool into a rack, drag them onto a board to form connected, dictionary-valid
words. The main mode is a village builder: magic words become buildings.
Repo: `vonerdenRyguy/Mr.Wordler`.

**Ignore `build/` and `.dart_tool/`** when exploring this codebase — both are
Flutter-generated output (already gitignored), not source.

## How we work

- The user designs features in the Claude app's design tool, which writes
  a numbered spec (`Desktop\MrWordlerScreenshots\specs\spec-NN-*.md`).
  A fresh Claude Code session builds one spec at a time on its own branch,
  in the spec's commit order, running `flutter analyze` + `flutter test`
  before every commit; puts it on the phone; walks the user through the
  spec's manual check list; and merges to master only on the user's OK.
  Before installing a build that touches saves, back up the phone's
  `shared_prefs/FlutterSharedPreferences.xml` (`adb exec-out run-as
  com.example.namer_app cat ...`).
- After a merge, fresh screenshots go into a new dated folder under
  `Desktop\MrWordlerScreenshots\` for the next design session.
- Phone: Samsung SM S926U (`flutter run -d R5CX213D2EJ`). If `flutter
  devices` says "not authorized", the user must tap "Allow USB debugging".
- **Building for the phone from Claude Code's shell** (found 2026-11-14):
  `adb` isn't on PATH; it's at
  `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`. Gradle fails with
  `Unable to establish loopback connection` unless
  `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=<a folder outside Temp>`
  is set (`%USERPROFILE%\.gradle\sock` works). If Gradle then hits
  `AccessDeniedException` under `build\app\intermediates\merged_native_libs`
  (OneDrive again), delete that folder and rebuild (if it names other
  folders under `build\`, delete all of `build\`). Building in the main
  folder needs Windows Developer Mode (plugin symlinks); it's on since
  2026-11-17. `flutter build apk
  --debug` then `adb install -r build\app\outputs\flutter-apk\app-debug.apk`
  updates the app and keeps its save.
- The phone's text size is 1.15, so `fits one screen` has to hold there,
  not just in the 390x844 test.
- OneDrive sometimes locks `build/unit_test_assets`; `rm -rf` it and
  re-run `flutter test`.

## Model choice

Before starting a task, say in one line whether it needs Opus (new feature
design, architecture, tricky bugs) or Sonnet (building from a spec, tests,
installs, small fixes). If I'm on the wrong one, tell me to switch with
`/model`.

## Current state (as of 2026-11-17)

Built from specs 01-14, **all merged to master**. Specs 04 and 05 were
merged together on 2026-11-14 after Ryan checked them on the phone
(spec-05's branch sat on top of spec-04's):
- **spec-01:** Infinite Estate's 10-tile rack with balanced refill
  (`lib/game/balanced_draw.dart`), Swap, and village save
  `saveVersion` 2 (v1 21-letter racks migrate once on load).
- **spec-02:** `LetterTile` (cream wooden tiles, Lilita One) and
  word-landing feedback (`tileLandingProvider`, banner, haptic).
- **spec-03:** one look for the whole app (see Design system), Home,
  start pages, the shared 10x10 game layout with a Leave confirm.
- **spec-04** (branch `spec-04-see-your-village`, merged):
  - **Angled Village view** (`lib/village/iso_village_view.dart`): every
    word on its own squares; magic words are raised letter blocks with
    their building sprite on top, other letters are stone path slabs.
    Tap a building or word for a card with what it means
    (`village_cards.dart`, `DefinitionService`). Switching views keeps
    the same center cell and zoom (`iso_math.dart`). A "Build your first
    building" helper shows until there's one.
  - Word scanning keeps repeats (`currentWordRuns`), so two WELLs are two
    buildings.
  - **Coins:** +10 the first time each building is built; 1 free Swap per
    visit (2 with a Farm) (`lib/village/village_rewards.dart`).
  - **Free Play and Theme Rush are removed.** Their stored data
    (`leaderboardEntries`, `themeRushBestSeconds`) is left in storage.
  - Home fits one screen with a live picture of your village; "Daily
    Estate Challenge" is now **"Daily puzzle"** everywhere it's shown.
  - **Settings:** Text size (Normal/Large/Extra large) and Reduce motion
    (`lib/settings/settings_controller.dart`), How to play.
- **spec-05** (branch `spec-05-word-of-the-day`, cut from spec-04's
  branch, merged). The spec was drafted by Claude Code
  from spec-04's outline, not from the design canvas; its `Decisions I
  guessed` table lists the ten choices Ryan approved as written.
  - **Themed Daily** (`lib/daily/daily_puzzle.dart`, `daily_themes.dart`):
    each UTC day has a theme (8 themes x 16 words, in order) and a secret
    word from it. The 21 letters are the secret word plus a balanced fill,
    dealt through `GridConfig.initialRack` with **no draw pool and no
    Swap**. The Daily no longer reads the dictionary to start
    (`bonus_word_picker.dart` is gone).
  - **Clue** button in Swap's place (`ClueButton` in `game_layout.dart`):
    3 free clues a day (first letter; the meaning, or the last letter when
    offline; the whole word), saved per day in `dailyChallengeData` so
    leaving doesn't hand them back. `SecretWordStrip` above the board
    shows the theme and one slot per letter.
  - **Secret word bonus:** prize step up one (as before) plus 20/15/10/5
    coins for 0-3 clues (`secretWordCoins`), only if the word is on the
    board at the winning Check. Player-facing text says `secret word`;
    saved JSON keeps the old `bonusWordFound` / `bonusWordsFound` names.
  - **Word of the day** (`lib/daily/word_of_the_day.dart`, 120 bundled
    words with meanings in `assets/words/word_of_the_day.json`): a card
    on Home (the village picture is now 150px to make room), and +10
    coins once a day for having the word spelled in your village
    (`word_of_the_day_controller.dart`, key `wordOfDayData`). The reward
    shows as a SnackBar, not the word-landing banner, so it also works for
    a word that was already on the board.
- **spec-06 word levels** (branch `spec-06-word-levels`, merged to
  master 2026-11-15 after Ryan's phone check; it also carries the
  Portfolio text fix from `tidy-portfolio-text`). Step 1 of the
  family game (see "Product direction").
  - `lib/settings/word_level.dart`: `WordLevel` sprout / explorer /
    builder / wordsmith, each with a `WordLevelInfo` (letters 8/12/16/21,
    board 6/8/10/10, clue ladder, leftover letters allowed, clock or not).
    Saved as `wordLevel` by `SettingsController`; unset = Wordsmith.
  - `dailyPuzzleFor(date, level)`: same theme for everyone; Wordsmith is
    byte-for-byte the old puzzle; Sprout words (3-4 letters, with
    meanings) are in `lib/daily/daily_easy_words.dart`.
  - The Daily round reads everything from the level: Sprout has no
    Check/Give up and ends when the hidden word is spelled
    (`finishOnSecretWord`), Explorer wins with 2 letters left
    (`dailyCheckOutcome`), neither shows a clock.
  - `WordLevelScreen` (Settings > Word level; also shown before a brand
    new player's first Daily, from `HomeScreen._openDaily`).
  - "Hear the word" on the Sprout result uses `flutter_tts` through
    `wordSpeakerProvider` (`lib/dictionary/word_speaker.dart`). Pinned to
    4.0.2: newer versions need Kotlin 2 / compileSdk 36, which this
    project's Gradle setup (AGP 7.3, Kotlin 1.9.24) can't build.
  - Home's village picture is `Expanded` around a `MinHeightBox`
    (`lib/ui/min_height_box.dart`), so Home fills exactly one screen
    whenever its content fits and only scrolls at very large text.

- **spec-07 a family on one phone** (branch `spec-07-family-one-phone`,
  merged to master 2026-11-15 after Ryan's phone check). Step 2
  of the family game.
  - `lib/players/players.dart`: up to 6 `Player`s (id, name, color),
    `playersProvider`, and `PlayerKeys.prefix`. **Every per-player save
    key is `PlayerKeys.of('key')`**: portfolioData, modeStatsData,
    dailyChallengeData, wordOfDayData, infiniteEstateVillageSave,
    wordLevel. The first player's prefix is empty, so the pre-spec-07
    save *is* player one (no migration); others are `p2_`, `p3_`...
    Each controller reads the prefix once when created, and its provider
    watches `currentPlayerIdProvider` so it is rebuilt on a switch. A
    new per-player save must do both. Text size, Reduce motion, dark
    mode and the definition cache stay shared.
  - `lib/players/family_word.dart`: the family word (key
    `familyWordData`, shared by the phone). `recordPlayed` (called from
    the Daily's `_finish`) uncovers a player's share; `guess` finds it
    early (20 coins each, else 10); coins are `owed` per player and paid
    by `claimFamilyCoins` (`family_widgets.dart`) when they next hold
    the phone, after `PortfolioController.ready`.
  - `main.dart` `AppRoot`: `WhoIsPlayingScreen` when there are 2+
    players and `playerPickedProvider` is false, else `HomeScreen`
    keyed by player id.
  - Screens: `lib/screens/players_screens.dart` (Who's playing, Add /
    change player, Pass the phone) and `family_screens.dart` (Family
    word, The family, Visit a village: look only).
  - One player alone sees nothing new except Settings > "Players on this
    phone".

- **spec-08 accounts and a family code** (branch `spec-08-family-online`,
  merged to master 2026-11-16 after Ryan's phone check). Step 3 of the
  family game; the first step with a server.
  - **Firebase** project `mr-wordler` (Ryan's Google account, free Spark
    plan): Authentication (Google, email link, anonymous) and Firestore
    (nam5). `firebase/firestore.rules` is what's published;
    `firebase/SETUP.md` lists every console step. Packages: firebase_core
    3.10.0, firebase_auth 5.4.0, cloud_firestore 5.6.0, google_sign_in
    6.2.1, app_links 6.3.0. minSdk is 23.
  - `android/app/google-services.json` is **gitignored**; download it
    from Project settings > Your apps (the browser pane can't save
    downloads). Without it the app builds and Family online says it isn't
    switched on (`firebaseReady`).
  - **Hosting** serves `firebase/hosting/`: `.well-known/assetlinks.json`
    (debug key's SHA-256) is what makes emailed sign-in links open the
    app; `finishSignIn/` is a fallback page. Deploy is Ryan's to run
    (`npx firebase-tools login`, then `deploy --only hosting` in
    `firebase/`); Claude Code's shell isn't allowed to.
    `pm get-app-links com.example.namer_app` shows "verified" when right.
  - `lib/online/`: `FamilyBackend` (interface + codes, in
    `family_online_models.dart`), `FirebaseFamilyBackend` (each player has
    a named FirebaseApp, the first uses the default one),
    `FakeFamilyBackend` for tests, and `FamilyOnlineController`
    (`familyOnlineProvider`, saved per player as `familyOnlineData`).
    Signing in reads the account's saved family (`savedFamilyId`).
  - Rules of the game: birth month and year first (only the year is
    kept); under 13 signs in anonymously and never gives an email; only a
    grown-up starts a family; **every** new member asks and a grown-up in
    the family says yes; a code preview shows only the grown-ups' names.
    Codes are a word + 4 digits from 2-9 (BEAR 4821).
  - Screens: `lib/screens/family_online_screens.dart`, reached from
    Settings > Family online and the family page. A finished Daily marks
    the player as played (`markPlayed`).
  - Before going public: privacy policy, a lawyer's look at the under-13
    consent step, a release key (its SHA-1/256 into Firebase and
    assetlinks.json), a real package name.

- **spec-09 family word and family map online** (branch
  `spec-09-family-word-online`, merged to master 2026-11-16 after the
  Pixel check; Child 1 finishing the word on the Samsung waits for a
  later day). Step 4 of the family game.
  - In an online family everyone plays the online family's word (the
    spec-07 word for the UTC day). Finishing the Daily uncovers your
    share of the hidden letters; the last to play uncovers the rest, so
    order never matters. A guess can find it early (+20 coins each, else
    +10), collected on each person's own phone. Family streak.
  - Server: `families/{fid}/days/{dayKey}` (`found`, `solved`,
    `solvedEarly`, `solvedBy`, `streak`), changed only in the
    `changeDay` transaction (`uncoverShare`, `solveByGuess`). Member docs
    gain `buildings`, `newBuildings`, `newOn`.
  - The family map shares **buildings only**: one plot per member around
    a Town Square marked "coming later"; tap a plot for its buildings and
    "new today". Buildings are sent when Home loads your village
    (`syncBuildings`; a brand-new village sends once even when empty).
  - Screens: `lib/screens/family_word_online_screens.dart`.
- **spec-10 helping each other** (branch `spec-10-helping`, cut from
  spec-09's, merged 2026-11-16 after a check on the Pixel and the
  Samsung). Step 5 of the family game.
  - **Letter gifts:** 3 a day per giver (`kGiftsPerDay`), free. They land
    in the receiver's village rack as bonus tiles past the 10
    (`addGiftLetter`), at most 5 a visit, with a gold stripe that follows
    the letter (`GridRackView.stripes`). A box says who sent them, with
    "Say thank you" (the `thanks` sticker).
  - **Asking:** one letter a day on your own plot (member `wants` /
    `wantsOn`); anyone can answer, and a gift of that letter that day
    answers it.
  - **Cheers:** 12 big stickers with a word each (`kStickers`), no typed
    text anywhere. The "From your family" card on Home and its page
    list gifts, cheers and open requests.
  - Server: `families/{fid}/notes/{id}` (kind gift/cheer, from, to, day,
    letter or sticker, about); create-only, deleted by sender or
    receiver; the controller watches today and yesterday and cleans up
    older ones. Claimed gift ids are kept per player in
    `familyOnlineData.claimedGifts`. Rules in `firebase/firestore.rules`
    (published 2026-11-16).
  - Code: `lib/online/helping.dart`, `lib/screens/helping_screens.dart`.
- **spec-11 Home as swipe pages** (branch `spec-11-home-pages`, merged
  2026-11-16 after a check on both phones). Ryan asked for a less
  cluttered Home, like Clash Royale's swipeable tabs.
  - `HomeScreen` is a `PageView` of **Me | Play | Family**, opening on
    Play, with `PageDots` and a slim `HomeTabBar` (`lib/ui/home_nav.dart`;
    swiping is the main way around). Play: village picture, Daily card
    (calendar tile, theme, level chip), Time Attack card. Me: level ring,
    word of the day, four squares (Word journal, My properties, My stats,
    Word level). Family: banner, family word, "From your family", two
    squares (online: Family map + Cheer someone; one phone: The family +
    Pass the phone); no family yet: "On this phone" / "On different
    phones". The Family tab's red number counts new help items.
  - Boxes fill the page with `_grow(flex, min)`: an `Expanded` around a
    `MinHeightBox` whose min grows with text size, so big text scrolls
    (never a scroll bar) instead of squeezing. Must fit one screen on the
    Samsung at 1.15 (tested at 411x891).
  - **Mr. W's tips** (`lib/screens/home_tips.dart`, `homeTipFor`): at most
    one per page, only when useful; the X hides it for the day
    (`hiddenTips`); Settings > Show tips (`showTips`). First-time "Swipe
    to look around" card (`homeIntroSeen`). All three keys are per phone.
    Tests that pump `MyApp` call `skipHomeIntro()` /
    `goToHomePage()` from `test/home_test_helpers.dart`.

- **spec-12 game feel** (branch `spec-12-game-feel`, merged 2026-11-16
  after Ryan's phone check). Came out of the research note
  `Desktop\MrWordlerScreenshots\research\2026-11-16-what-games-do.md`.
  - **Sound** (`lib/sound/sound_service.dart`): audioplayers 6.1.0 (builds
    with AGP 7.3). Sounds and three music loops are generated by
    `dart run tool/make_sounds.dart` into `assets/sounds/`. `soundProvider`
    (`play(Sfx)`, a music stack `enterMusic`/`leaveMusic`), `MusicScope`
    per screen (village from the root, Daily, Time Attack),
    `SoundLifecycle` pauses in the background, `playSfx(context, ...)`
    for plain widgets. Silent under `FLUTTER_TEST`; tests override
    `soundBackendProvider` with `FakeSoundBackend` (`test/sound_test.dart`).
    Mixes with other audio and doesn't follow the silent switch.
  - Settings: Music / Sounds switches + volumes (per phone; keys
    `musicOn`, `musicVolume`, `soundsOn`, `soundsVolume`).
  - **Reward moments** (`lib/ui/reward_moment.dart`, `showRewardMoment`):
    word of the day, family word coins, and the new-building moment
    (ribbon, drop-in, Hooray!). Coins are paid *before* it opens; Collect
    only animates them into its own counter.
  - **Play page:** pages fill the screen and the top bar / tip / dots /
    tabs float over them (measured; pages read `MediaQuery.padding`).
    Village backdrop, gold PLAY (Daily until played, then the village),
    round Daily (red !) and Time Attack badges.
  - `ChunkyButton` bounces; `ChunkyCard` without `onTap` has no outline
    or lip (soft shadow) so tappable things stand out.
  - Low-latency sounds must `stop()` before each `play()`: Android's
    SoundPool player otherwise resumes the finished stream at its old
    volume (fixed in spec-12b).
- **spec-12b calmer Me** (merged 2026-11-16). Ryan found Me and Family
  crowded. Me is a profile: avatar in a big level ring, name, points to
  next level; word of the day as one strip (+10 / Done); one row of
  `_RoundButton`s: Journal, Homes, Stats, Word level. Family's clean-up
  comes with spec-13 (Town Square board D121).
- **spec-13 Town Square** (branch `spec-13-town-square`, merged with
  spec-14 on 2026-11-17 after Ryan's Pixel check). Step 6 of the family
  game; online families only (Ryan: shared devices are for kids, not
  grown-ups).
  - `lib/online/town_square.dart`: six buildings (`kSquareBuildings`),
    bricks (Daily +3, family word +5, new village building +2, gift or
    cheer +1; at most 5 at once), goal `squareGoal` = 15 x members (min
    30; `--dart-define=SQUARE_TEST_GOAL=n` for a test build), a weekly
    vote (`SquareVote`, closes when all voted or Monday UTC). Pure change
    functions `settleSquare` / `addSquareBricks` / `pickSquareBuilding`.
  - Server: `families/{fid}/square/state`, changed only in
    `changeSquare` transactions; `bricks` only goes up (finished buildings
    move bricks to `spent`) so the rules can check it. Rules published
    2026-11-16.
  - The online Family page is `TownSquarePage`
    (`lib/screens/town_square_screens.dart`, art in `square_art.dart`);
    "We built it!" (`celebrateSquare`, +15 coins) shows once per phone,
    counted in `familyOnlineData.squareSeen`.
- **spec-14 building art and wallpaper** (branch `spec-14-building-art`,
  merged 2026-11-17 after Ryan's Pixel check; Samsung not checked).
  Canvas boards H141-H144.
  - Raised letter blocks are back (spec-13's ground lots were undone).
  - Buildings are drawn in code (`lib/village/building_art.dart`,
    `paintBuilding`), covering their word's whole run of blocks: a window
    per letter, door on the middle one. Crossing building words: the later
    one covers the longest stretch not already used
    (`VillageScene.buildingCells`); `buildingDepth` orders buildings so
    one in front always draws after. Taps use `buildingOutline`. The
    sprites in `assets/village/buildings/` are only used for tap cards now.
  - Wallpapers (`lib/ui/wallpaper.dart`): `pattern` behind every
    `WordlerScaffold` page and the offline Family page; `hills` behind Me
    and `ModeStartView`. Home's floating bars show the same picture
    (`WallpaperSlice`).

## Product direction (set by Ryan, 2026-11-14)

Mr. Wordler is becoming a **cooperative word game for families**, aimed
especially at kids and older players; a friends-group mode comes later.
Each person keeps their own plot; a shared world grows from things the
family does together. Approved build order (each a spec, drawn on the
design canvas first and approved there before any code):

1. Word levels (spec-06, merged).
2. A whole family on one phone (spec-07, merged): several players, each
   with a plot and a level; a daily family word solved by passing the
   phone. No server.
3. Accounts and a family code (spec-08, merged; Firebase).
   Child-privacy decisions are Ryan's.
4. Family word and family map online (spec-09, merged).
5. Helping: letter gifts, requests, ready-made cheers, no open chat
   (spec-10, merged).
6. Town Square, weekly family vote (spec-13, merged); family level and fog
   still to come.
7. Playing together: Word bridge (turn-based first), Word buddies.

### Next direction: Explore (Ryan, 2026-11-18/19)

Ryan doesn't enjoy playing yet ("good but not engaging"). The hook will be
**exploring**, not collecting resources. The harvest / building-upgrade
boards (canvas row "spec-15 ideas", K151-K156) are **tabled**. Ryan
approved all of the ideas below. Before any code: rethink the family
game for this, then mock everything up on the canvas.
- **Fog and regions:** the village starts in a clear meadow; words clear
  fog. Rings outward need longer words (Meadow 3+, Forest 4+, River 5+,
  Hills 6+, Mountains 7+), scaled down by word level (Sprout's mountains
  ask for 4). Same map every time: generated from a fixed seed and saved.
- **Special tiles to reach (these are what you collect):** treasure
  chests (coins, golden letters), villagers, shrines that unlock features
  (Swap, bigger rack, music...), ruins rebuilt with a themed word, rivers
  crossed only by a word long enough to span them, boulders with a fixed
  letter to spell through, golden double-XP squares, big landmarks
  (waterfall, castle, lighthouse).
- **XP for every new word** (more for long words, rare letters, first
  discoveries); levels give small treats, the map gives the big goals.
- **Little people:** connect a word to one and they move in, wander your
  word paths (later with purpose: home, job), can be named, and have
  wishes ("a word about cats"); this replaces "village orders".
- **Later:** day/night and seasons, Mr. W story quests, a discovery
  journal of everything found, a family fog map.
- **Shared island (family, approved 2026-11-19):** the whole family lives
  on one map. Each person's village starts at its own spot on the coast,
  with fog between. Fog anyone clears is cleared for everyone. A word that
  touches a family member's word joins the two villages with a road (a big
  shared moment). A family landmark in the center fog (e.g. a ruined
  lighthouse) is restored by reaching it from all sides; it replaces the
  Town Square bricks (the vote can stay). Villagers visit along roads.
  Nobody changes anyone else's tiles; each side's region rules follow
  that person's word level. Extras: keys found on one side that open a
  gate on another's, and a shared family discovery book.
  Open: what's in the middle; one-phone families; where new members start.
- **Play together (approved 2026-11-19):** live co-op mini-games when two
  family members are on at once, like Clash Royale's friendly battle but
  family vs the puzzle. Ryan's seed: given a meaning and some letters,
  spell the word together. Details still to design.
- **Build order:** spec-15 Explore (fog, regions, special tiles, XP; map
  made ready for several villages), spec-16 Villagers, spec-17 Shared
  island, spec-18 Play together, spec-19 day/night, seasons, quests.
- Keep it gentle: no region locked forever; a hint when stuck.

The design canvas is the claude.ai artifact "Mr. Wordler - App Flow"
(https://claude.ai/artifact/C4fYPKs7owUmfUDfM1VK7L): rows for the family
concept, each spec's proposal, and dated real-phone screenshots.

## Key architectural decisions

- **Riverpod** (`flutter_riverpod`) for all real game state via
  `StateNotifierProvider`; legacy `provider` package is kept *only* for
  `ThemeNotifier` (dark mode), imported with `hide ChangeNotifierProvider`
  (and `hide Consumer` in `main.dart`).
- **One shared grid engine** (`lib/game/`) backs every mode. Each mode
  screen wraps its content in its own `ProviderScope(overrides:
  [gridConfigProvider.overrideWithValue(...)])` so modes never share
  state. `gridGameControllerProvider` intentionally throws if
  `gridConfigProvider` isn't overridden.
- **Lazy rendering for the 500x500 board.** Words view (`GridBoardView`
  with `cellSize`) builds only visible cells inside
  `InteractiveViewer.builder`; Village view is one `CustomPainter` that
  paints only visible cells (grass as one checker path; letters, blocks
  and buildings only for occupied cells).
- **Village view is a pure rendering of the board**, not a separate data
  model: `computeStructures(runs)` (`lib/village/structures.dart`) derives
  buildings fresh each time, and `VillageScene` holds the geometry both
  painting and tap hit-testing use. Only board/rack/pool plus
  `reachedLandmarks`, `discoveredWords` and `lastCashedOutScore` are saved
  (`village_save.dart`).
- **Word checks are injectable:** `wordCheckProvider` (defaults to the
  dictionary) is used by word-landing feedback and the village word scan,
  so tests can fake it (the real 1.5MB dictionary can't load in tests).
- **Accessibility-first for Village Builder** (explicit user directive):
  no timers, no punishing fail states, gentle positive feedback only.
  Tile letters never grow with text size (`TextScaler.noScaling`); the
  whole rack must always fit.
- **The word-landing banner can carry a note** (`landingNoteProvider`,
  default none): the Daily overrides it so the secret word lands as
  `HORSE · Secret word!`.
- **Verification policy:** risky changes go on a feature branch with
  analyze + test before every commit and an on-device check before merge.

## Design system (spec-03)

- **Every color, text style, size and radius comes from
  `lib/ui/tokens.dart`** (`WColors`, `WModeColors`, `WText`, `WSize`,
  `wLip()`); `buildWordlerTheme()` is the app's one ThemeData.
  `test/tokens_test.dart` checks WCAG contrast and fails if
  `Colors.deepPurple/orangeAccent/greenAccent` come back. Nothing is
  smaller than 14px text.
- Fonts are bundled: **Lilita One** (titles, buttons, numbers, tiles) and
  **Atkinson Hyperlegible** (everything else), in `assets/fonts/`.
- Shared widgets in `lib/ui/`: `ChunkyButton`/`ChunkyIconButton`,
  `ChunkyCard`, `PillChip`, `WordlerScaffold`, `WordlerDialog`/
  `showWordlerDialog` (each action closes the dialog first),
  `ModeStartView`, `GameLayout` + `confirmLeaveRound`,
  `check_result_dialog.dart`.
- Light theme only: `darkTheme` points at the same theme and the switch is
  hidden; `ThemeNotifier` and its saved value are untouched.

## Code organization

```
assets/
  fonts/             Lilita One, Atkinson Hyperlegible (+ OFL licenses)
  images/            village_preview.png (Home picture with no village yet)
  words/             word_of_the_day.json (120 words + plain meanings)
  village/           buildings/*.png (sprites), cards/*.png (tap-card art),
                     buildings.json (sprite anchors: the pixel that sits on
                     the ground at the word's middle cell)
lib/
  game/              Shared grid engine
    grid_config.dart, grid_game_state.dart, grid_providers.dart, tile_location.dart
    grid_game_controller.dart  Move/draw/trade/swap; currentWordRuns()
    balanced_draw.dart        Infinite Estate's balanced refill rules
    letter_tile.dart          LetterTile (+ TileFx animation, stripe, faceColor)
    word_runs.dart            WordRun; across/down runs through a cell
    word_landing.dart         tileLandingProvider, wordCheckProvider, fxFor
    word_landing_banner.dart  The "CAT" banner over the board
    grid_board_widget.dart    GridBoardView/GridRackView/GridTileWidget + GridTheme
  ui/                Design tokens + shared chunky widgets
  screens/
    home_screen.dart          Swipe pages Me | Play | Family (spec-11)
    home_tips.dart            Mr. W's tips + hidden-for-today
    mode_start_pages.dart     Time Attack's start page
    time_attack_screen.dart, daily_challenge_screen.dart
    infinite_estate_screen.dart  The village (Words + Village views)
    portfolio_screen.dart, stats_screen.dart, settings_screen.dart
    Navigation: Home -> Time Attack start page -> round (Start replaces the
    start page, so leaving returns Home); Home -> "Visit your village" and
    the Daily card go straight in.
  village/
    magic_word.dart           The 8 magic words + their building defs
    structures.dart           BoardStructure, computeStructures(runs), stripes
    iso_math.dart             Isometric projection + view-switch camera helpers
    iso_village_view.dart     IsoVillageView, VillageScene, hitTestVillage
    building_art.dart         The eight buildings drawn in code (spec-14)
    village_art.dart          Loads buildings.json + sprites (with alpha)
    village_cards.dart        Building/word/meaning cards, first-building helper
    village_rewards.dart      First-building coins, free Swaps
    landmark.dart, bridge_transform.dart
    discovery_journal_view.dart  Journal sheet (+ "What it means")
    village_save.dart, village_save_migration.dart
  settings/          settings_controller.dart (textSizeStep, reduceMotion)
  portfolio/         Neighborhoods/property tiers/currency/XP
  daily/             Daily puzzle: daily_themes, daily_puzzle (theme, secret
                     word, 21 letters), clues + streak (daily_challenge_*),
                     daily_tier (prize step, secretWordCoins), share_card;
                     word_of_the_day + its once-a-day claim controller
  stats/             Mode stats (Infinite high score; old Theme Rush times kept)
  dictionary/        Tap-for-definition (dictionaryapi.dev, cached locally)
  components/        Timer, word validator (findValidRuns), letter generator
  util/              ThemeNotifier (dark mode, legacy `provider` package)
```

SharedPreferences keys: `infiniteEstateVillageSave`, `portfolioData`,
`dailyChallengeData`, `modeStatsData`, `leaderboardEntries` (unused since
spec-04, kept), `isDarkMode`, `textSizeStep`, `reduceMotion`, `wordOfDayData` (spec-05),
`familyWordData` (spec-07), `familyOnlineData` (spec-08, per player;
spec-10 adds `claimedGifts` inside it), `homeIntroSeen`, `showTips`,
`hiddenTips` (spec-11, per phone), `musicOn`, `musicVolume`, `soundsOn`, `soundsVolume` (spec-12, per phone),
`definitionCache_*`.

## Testing

- `flutter analyze` — clean except the pre-existing `bananagramsTiles.dart`
  filename-casing lint.
- `flutter test` — 242 tests as of spec-14 (220 as of spec-12b).
  `test/family_word_online_test.dart` and `test/helping_test.dart` play
  out the family word, map and helping on the fake server.
  `test/family_online_test.dart` plays out families on the fake server. `widget_test.dart` loads the
  real fonts (`loadAppFonts`) so layout-fit checks match the phone.
- Prefer the real phone for visual checks; `adb exec-out screencap -p`
  grabs a screenshot.

## Known open items / next steps

1. **Still to see on a phone:** spec-09 steps 2-4 (Child 1 finishes the
   family word on the Samsung; +10 coins each; Child 1's +20 for an
   early guess) and step 8 (the shared list when someone asks to join);
   the spec-10 gift box for several letters on the Samsung (it was
   interrupted by another app on 2026-11-16; a widget test covers it).
1. **Second test phone:** a Pixel 7 (`2B141FDH2006VR`) on a secondary
   user profile: install with `adb -s 2B141FDH2006VR install -r --user
   10 ...` and read prefs with `run-as com.example.namer_app --user 10`.
1. **Left out of spec-07:** removing a player, and tapping a word for its
   meaning while visiting a village.
1. **Explorer and Builder on the phone:** only Sprout could be played on
   the day spec-06 was checked (one Daily a day); look at the other two
   levels on a later day.
1. **Daily with no Swap:** keep watching for a Daily that leaves one
   letter fitting nowhere; the planned fix is letting a round finish with
   a letter or two left over for a lower prize.
2. **spec-06:** building upgrades, village level, building plans,
   districts. Later: a Word book page, hints/assist mode, power-ups.
3. **Dark palette** (the app is light-only; switch hidden).
4. **Ocean Ave's "+15s starting time" perk** isn't applied by Time Attack
   yet (fixed 3:00).
5. **Well's once-per-visit limit** and the free Swaps reset when the
   village screen reopens (session-only, not saved), by design.
6. Rack pins are intentionally not saved across sessions.
7. The Village view chip row (score, buildings, Journal) wraps to two
   lines on the S24+; worth a design look.
