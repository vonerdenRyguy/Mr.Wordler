# Mr. Wordler

A Bananagrams-style word tile game (Flutter/Dart). Draw letter tiles from a
pool into a rack, drag them onto a board to form connected, dictionary-valid
words. Repo: `vonerdenRyguy/Mr.Wordler`.

**Ignore `build/` and `.dart_tool/`** when exploring this codebase — both are
Flutter-generated output (already gitignored), not source.

## Current state (as of 2026-10-01)

- `master` is up to date through commit `47a880f` (fast-forward of
  `village-fixes`, merged 2026-10-01 after the user confirmed on-device
  that it looks right): all game modes, the Portfolio meta-progression
  system, the Village Builder pivot through "structure abilities"
  (milestone 5), the board-rendering rework, and the Village fixes —
  bonus letters now get a one-off extra rack slot (Infinite Estate's
  rack is always full), rack pins follow the letter rather than the
  slot, and the Village AppBar/rack layout no longer cuts off the
  bottom rack row.
- **In progress (2026-10-02): design specs 01-03** from
  `Desktop\MrWordlerScreenshots\specs\`, built in order, one branch
  each, each checked on the phone and merged only on the user's OK
  before the next starts.
  - `spec-01-infinite-rack`: Infinite Estate rack is now **10 tiles**
    (2 rows of 5) with **balanced refill** (`lib/game/balanced_draw.dart`,
    `GridConfig.balancedRefill`: keeps 3-4 vowels, max 2 hard letters
    J/K/Q/V/X/Z, no doubled hard letter, no Q without U), a **Swap
    letters** button (`GridGameController.swapRack`, 5 coins via
    `PortfolioController.spendCurrency`, pinned letters kept), and the
    **Farm now gives one free Swap per visit** (its old balanced-refill
    ability became the default; `preferBalancedRefill` is gone). Village
    saves have **`saveVersion` 2**; version-1 saves (21-letter rack) are
    migrated once on load by `lib/village/village_save_migration.dart`
    (first 10 rack letters kept, the rest go back to the pool). The 10x10
    modes are unchanged.
    Merged to master 2026-10-02 (`4a92d1c`) after on-device check.
  - `spec-02-tile-visuals`: every board/rack tile is a `LetterTile`
    (`lib/game/letter_tile.dart`): cream wooden face, ink outline, bottom
    lip, bundled **Lilita One** font (`assets/fonts/`). Word-landing
    feedback in the shared engine: `lib/game/word_landing.dart`
    (`tileLandingProvider` watches the grid state; exactly one new board
    letter = a landing; valid words via the overridable
    `wordCheckProvider`) + `word_runs.dart` + `word_landing_banner.dart`
    (banner over the board, outside its zoom). Settle bump, pop + gold
    glow on new words, one light haptic, nothing for invalid words;
    respects system "remove animations". No saved data changes.
  - Next: spec-03 (one look for the whole app).
- On-device runs: phone is a Samsung SM S926U (`flutter run -d
  R5CX213D2EJ`). If `flutter devices` says "not authorized", the user
  needs to accept the USB-debugging prompt on the phone.

## Key architectural decisions

- **Riverpod** (`flutter_riverpod`) for all real game state via
  `StateNotifierProvider`; legacy `provider` package is kept *only* for
  `ThemeNotifier` (dark mode), imported with `hide ChangeNotifierProvider`
  to avoid clashing with Riverpod's own.
- **One shared grid engine** (`lib/game/`) backs every mode. Each mode
  screen wraps its content in its own `ProviderScope(overrides:
  [gridConfigProvider.overrideWithValue(...)])` so modes never share
  state, while `GridBoardView`/`GridRackView`/`GridTileWidget` and
  `GridGameController` are reused everywhere. `gridGameControllerProvider`
  intentionally throws if `gridConfigProvider` isn't overridden, so a
  missing override fails loudly instead of silently sharing state.
- **Lazy board rendering for large boards.** `GridBoardView` and
  `VillageBoardView` default to the original eager `GridView.count`
  (fine for every 10x10 mode), but take an optional `cellSize` that
  switches them to `InteractiveViewer.builder` — fixed-pixel-size cells,
  laid out at real `(col*cellSize, row*cellSize)` positions, with only
  cells intersecting the current viewport actually built. This is what
  lets Infinite Estate's board be 500x500 without eagerly constructing
  250,000 widgets. See `lib/game/grid_board_widget.dart` and
  `lib/village/village_board_view.dart`.
- **Village view is a pure rendering switch**, not a separate data model:
  `computeStructures()` derives "structures" fresh from the live board's
  word positions every time. Only the actual board/rack/pool plus a few
  event-tracking sets (`reachedLandmarks`, `discoveredWords`,
  `lastCashedOutScore`) are persisted (`lib/village/village_save.dart`,
  via `shared_preferences`).
- **Accessibility-first for Village Builder** (explicit user directive):
  no timers, no punishing fail states, gentle positive feedback only.
  Landmark/Well rewards are always upside, never a penalty.
- **Verification policy** (established after a Riverpod scoping bug once
  reached the user's device despite passing tests): large/risky changes
  go to a feature branch, not directly to master, with `flutter analyze`
  + `flutter test` run before every commit, and an explicit note of what
  hasn't been visually confirmed on-device.

## Code organization

```
lib/
  game/              Shared grid engine used by every mode
    grid_config.dart         Per-mode config (board/rack size, seed, refill behavior)
    grid_game_controller.dart  Core move/draw/trade/swap logic (StateNotifier)
    balanced_draw.dart        Infinite Estate's balanced refill rules
    letter_tile.dart          LetterTile: the one tile look, + TileFx animation
    word_runs.dart            Across/down runs through a board cell
    word_landing.dart         tileLandingProvider, wordCheckProvider, fxFor
    word_landing_banner.dart  The big "CAT" banner over the board
    grid_game_state.dart      Immutable state (board/rack/pool cells)
    grid_board_widget.dart    GridBoardView/GridRackView/GridTileWidget + GridTheme
    grid_providers.dart       gridConfigProvider / gridGameControllerProvider
    tile_location.dart        TileZone/TileLocation (drag payload)
  screens/           One file per mode/top-level screen
    menu_screen.dart, mode_select_screen.dart, game_screen.dart (Free Play),
    daily_challenge_screen.dart, time_attack_screen.dart, theme_rush_screen.dart,
    infinite_estate_screen.dart (Village Builder — the biggest/most actively
    developed screen), portfolio_screen.dart, stats_screen.dart, settings_screen.dart
  village/           Village Builder-specific logic, layered on the grid engine
    magic_word.dart           Curated list of ~6-8 magic words + their structure defs
    village_board_view.dart   Read-only "Village" map rendering (structures/landmarks)
    landmark.dart             Formula-based landmark placement (fraction-of-radius
                               from board center, golden-angle spread)
    bridge_transform.dart     Pure pan/zoom-to-cell transform math (Bridge ability)
    discovery_journal_view.dart  Journal bottom sheet + "letters toward word" logic
    village_save.dart         Persistence (SharedPreferences), saveVersion
    village_save_migration.dart  v1 (21-letter rack) -> v2 (10) save migration
  portfolio/         Neighborhoods/property tiers/currency/XP meta-progression
  daily/             Daily Estate Challenge (seeded puzzle, bonus word, streak)
  stats/             Per-mode stats tracking
  theme_rush/        Theme Rush's theme/word-list data
  dictionary/        Tap-for-definition (dictionaryapi.dev, cached locally)
  components/        Shared low-level widgets (tiles, timer, word validator)
  util/              ThemeNotifier (dark mode, legacy `provider` package)

test/                Mirrors lib/ for the pieces with real logic (grid engine,
                     village, dictionary, bonus-letter rules); widget_test.dart
                     covers full-app smoke tests per mode.
```

## Testing

- `flutter analyze` — should always be clean except the one pre-existing
  `bananagramsTiles.dart` filename-casing lint (long-standing, not worth
  a rename mid-feature).
- `flutter test` — 77 tests across `test/*.dart` as of this writing, all
  passing on `master`.
- No real device/emulator is reliably available in this environment by
  default — when one is connected (`flutter devices`), prefer running on
  it (`flutter run -d <id>`) over Windows desktop (needs Developer Mode
  enabled, usually off) for visual verification. `flutter screenshot -d
  <id> -o <path>` can grab a real on-device PNG once the app is running.

## Known open items / next steps

1. **Portfolio screen has leftover dev-only "Test controls"** (+10 coins /
   +50 XP / Award random tile buttons) — temporary stand-ins until Daily
   Estate Challenge / Time Attack / Theme Rush / Infinite Estate feed
   real rewards into Portfolio. Should be removed before this goes much
   further.
2. **Bridge's "jump to landmark" pan/zoom** has unit/property test
   coverage for its transform math but hasn't been visually confirmed
   on-device yet.
3. **Well's once-per-visit limit** resets on app restart rather than
   per village-visit (session-only state, not persisted) — confirm this
   is the intended behavior.
4. Rack tile pinning is intentionally *not* persisted across sessions
   (pure UI affordance, not a saved record) — confirm this is still
   wanted now that pins follow letters instead of slots.
5. A set of reference screenshots (4 mode screens, Portfolio x2, one
   Infinite Estate gameplay screen) was captured to
   `C:\Users\Ryan the Avatar\Desktop\MrWordlerScreenshots\` for handing
   off to a design-focused Claude session — the Infinite Estate
   one predates the `village-fixes` layout change and is now stale.
