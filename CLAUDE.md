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
- OneDrive sometimes locks `build/unit_test_assets`; `rm -rf` it and
  re-run `flutter test`.

## Current state (as of 2026-11-14)

Built from specs 01-05. Specs 01-03 are merged after an on-device check;
**spec-04 and spec-05 are built but not yet checked on the phone or
merged** (spec-05's branch sits on top of spec-04's):
- **spec-01:** Infinite Estate's 10-tile rack with balanced refill
  (`lib/game/balanced_draw.dart`), Swap, and village save
  `saveVersion` 2 (v1 21-letter racks migrate once on load).
- **spec-02:** `LetterTile` (cream wooden tiles, Lilita One) and
  word-landing feedback (`tileLandingProvider`, banner, haptic).
- **spec-03:** one look for the whole app (see Design system), Home,
  start pages, the shared 10x10 game layout with a Leave confirm.
- **spec-04** (branch `spec-04-see-your-village`, awaiting on-device
  check):
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
  branch, awaiting on-device check). The spec was drafted by Claude Code
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
    home_screen.dart          Level/coins, live village picture, Word of the
                              day, Daily puzzle, Time Attack, Portfolio/Stats
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
`definitionCache_*`.

## Testing

- `flutter analyze` — clean except the pre-existing `bananagramsTiles.dart`
  filename-casing lint.
- `flutter test` — 140 tests as of spec-05 (110 as of spec-04). `widget_test.dart` loads the
  real fonts (`loadAppFonts`) so layout-fit checks match the phone.
- Prefer the real phone for visual checks; `adb exec-out screencap -p`
  grabs a screenshot.

## Known open items / next steps

1. **On-device checks owed:** spec-04's manual check list, then
   spec-05's (section 8 of each spec), before either merges. For spec-05,
   watch for a Daily that leaves one letter fitting nowhere now that
   there's no Swap; the planned fix is letting a round finish with a
   letter or two left over for a lower prize.
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
