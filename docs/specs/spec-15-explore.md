# spec-15: Explore (fog, regions, special tiles, XP)

Status: **draft for Ryan's approval** (written 2026-11-19 by Claude Code from
the canvas row "Chapter 1 (Explore on a shared island) and the game wheel",
boards M161 and M162, and Ryan's answers recorded in CLAUDE.md under
"spec-15 decisions"). Model to build it: Sonnet.

## Why

Ryan: the game is "good but not engaging". Spelling words on an empty
500x500 board has no direction and no surprises. Explore gives every word a
purpose: clear the fog, reach what's out there, and see the village push
into new lands.

This spec is **solo** (your own village). The family's shared island is
spec-17 and villagers are spec-16, but the map is built so both can plug in
without a rewrite (see "Ready for later").

## What the player sees

1. **Fog.** Everything outside the area around your words is covered by soft
   fog, in both Words view and Village view. You can only drop letters
   where there's no fog.
2. **Words clear fog.** A real word that follows the rule of its region
   lifts the fog around every one of its letters.
3. **Regions in rings around home**, each with a sign and its own ground:

   | Region | From home (cells) | A word must have | Ground |
   |---|---|---|---|
   | Meadow | 0-11 | 3+ letters | today's grass |
   | Forest | 12-29 | 4+ letters | darker grass, trees |
   | River | 30-32 (water) | crossing it takes 5+ letters (land, 3 water, land) | water |
   | Hills | 33-59 | 6+ letters | light green, bumps |
   | Mountains | 60+ | 7+ letters | grey-green, rocks |

   The word level caps the length (Sprout 4, Explorer 5, Builder 6,
   Wordsmith 7): a region never asks for more than your level's cap. The
   river has **fords** (stepping-stone land cells across the water) about
   every 20 cells around the ring, so a 3-letter word can always cross
   somewhere. Nothing is ever locked forever.
4. **A word that's too short for its region** still stays on the board and
   still counts for the village score exactly as today. It just doesn't lift
   fog or give XP, and the landing banner says so kindly: `CAT · Forest
   words need 4 letters to clear fog`.
5. **Special tiles** sit on the map. Faint outlines show through the fog, so
   you can see where to aim:
   - **Chests:** reach one (a counted word with a letter on it) for a reward
     moment: coins (Meadow 10, Forest 15, Hills 25, Mountains 40) plus one
     bonus letter in the rack (the gift-letter tile with its gold stripe).
   - **Golden squares:** a counted word with a letter on one earns double
     XP. Each golden square works once.
   - **Shrines** (three, at fixed spots): each unlocks a new feature for
     good, with a reward moment that explains it:
     1. **Hint** (in the Forest): a Hint button, once per visit. It shows a
        word you can make from your letters and lights up where it fits.
     2. **Bigger rack** (just past the River): the rack grows from 10 to 11.
     3. **Compass** (in the Hills): a small arrow chip in the top bar
        pointing to the nearest special you haven't reached yet. A second
        Bigger rack shrine deep in the Hills takes the rack to 12.
6. **XP for every counted word**, paid at once into the existing
   portfolio XP (the same level ring as Me; no second level). A small
   purple `+12 XP` floats up from the word (board M162).
   - XP = 5 for 3 letters, 8 for 4, 12 for 5, 17 for 6, 23 for 7, +6 for
     each letter after that.
   - +3 for each J, Q, X, Z, K.
   - +5 the first time you ever spell that word (`spelledWords`).
   - Doubled on a golden square.
   - The Leave cash-out keeps working as today; this XP is on top.
7. **Level-ups in the village** show a reward moment: +1 free Swap for this
   visit and +20 coins. (Bigger racks come from shrines, not levels.)
8. **Top bar:** an XP chip (level number + bar), coins, and an **Island
   map** button (board M162).
9. **Island map** (board M161, solo version): the whole board zoomed far
   out. Revealed land in its region colors, fog over the rest, specials as
   icons (reached ones ticked), and a card: "Explored 6% · 3 chests found ·
   1 of 4 shrines". Tap anywhere revealed to jump the camera there.
10. **Your village today becomes the starting meadow.** Home is the board
    center (as it is now). On the first open after this update, the fog
    lifts around every letter already on the board, and every word already
    there counts as already counted (no surprise XP flood, nothing lost).

## Rules in detail

- **Fog grain:** the board is split into 4x4-cell chunks (125x125 chunks).
  A chunk is revealed or not. A counted word reveals the chunk under each
  of its letters plus the 8 chunks around each, so about one chunk of
  open land always sits ahead of your words. The meadow's chunks within
  11 cells of home start revealed.
- **Placement:** a tile can't be dropped on a cell in an unrevealed chunk.
  The drop is refused quietly: the tile goes back with the usual bounce
  and no sound of failure, plus a one-time tip from Mr. W, "Clear the fog
  with a word first". Picking up tiles is never blocked.
- **When a word counts:** after each board change, take
  `currentWordRuns(isValid: wordCheck)`. A run counts if it is a real word,
  is at least the required length, and its key (first cell index +
  direction + text) isn't already in `countedRuns`. The required length is
  the **highest** region minimum among its letters, capped by word level.
  A word with any letter on water is a River word (needs 5, capped).
  Counted runs reveal fog, pay XP, and claim specials under their letters.
  The board doesn't need to be fully valid and connected for a run to
  count; only that run must be a real word (same as structures today).
- **Moving tiles back:** fog never comes back and XP is never taken away.
  Re-spelling a run with the same key pays nothing.
- **Region edges** wobble by ±2 cells from seeded noise so rings look
  natural, not like perfect circles.
- **Specials are placed per chunk from the seed** (hash of seed + chunk
  x/y). No big table is stored.
  - Chests: none at random in the Meadow, but two fixed tutorial chests
    6-9 cells from home. 1 in 12 Forest chunks, 1 in 10 Hills chunks, 1 in
    8 Mountain chunks.
  - Golden squares: 1 in 10 chunks outside the Meadow.
  - Shrines at fixed distances (Hint 20, Bigger rack 36, Compass 48,
    Bigger rack 56), at seeded angles.
  - Nothing is placed on water or on a cell that already has a letter.
- **The existing 5 landmarks** (`landmark.dart`) stay exactly as they are.

## Ready for later (do these now, they're cheap)

- `IslandMap` takes a **home cell** and a **seed**, and exposes
  `regionAt(index)`, `specialAt(index)` and `homeCell`. Spec-15 uses one
  layout, `RingIslandMap` (rings around home). Spec-17 adds a shared-island
  layout (homes on the coast, harder toward the middle) behind the same
  interface.
- The generator already reserves **villager spots** (1 in 14 chunks outside
  the Meadow, plus one fixed spot 8 cells from home). Spec-15 neither draws
  them nor claims them; spec-16 turns them on.
- Per-player: the island save is per player (`PlayerKeys.of(...)`), and its
  provider watches `currentPlayerIdProvider`, like every other per-player
  save.

## Saves

`infiniteEstateVillageSave` goes to **saveVersion 3**, adding:
- `islandSeed` (int; new players get a random one, upgraded saves use a
  fixed 1 so tests are stable)
- `revealedChunks` (list of chunk ids)
- `countedRuns` (list of run keys)
- `spelledWords` (list of words)
- `claimedSpecials` (list of cell indices)
- `rackBonus` (0-2, from the Bigger rack shrines)
- `shrines` (list of unlocked shrine ids)

Migration v2 to v3 (in `village_save_migration.dart`, once on load) reveals
the chunks around every letter on the board plus the meadow, puts every
current real-word run into `countedRuns` and its word into `spelledWords`,
and leaves everything else empty. Back up the phone's prefs before
installing (see "How we work").

## Code plan

New files:
- `lib/explore/island_map.dart`: `IslandMap`, `RingIslandMap`, `Region` (with
  min length, sign text, ground colors), `SpecialKind`
  (chest, golden, shrine, villagerSpot), seeded noise, chunk math.
- `lib/explore/explore_rules.dart`: pure functions `requiredLength(run,
  map, level)`, `xpForWord(...)`, `countNewRuns(...)`, `revealFor(runs)`,
  `specialsClaimed(...)`.
- `lib/explore/explore_state.dart`: the saved island state + a controller
  (or fields in the village screen state, following how
  `_reachedLandmarks` works today, if that's simpler).
- `lib/screens/island_map_screen.dart`: the Island map page.

Changes:
- **Engine (`lib/game/`):** a placement guard. Add an optional
  `canPlaceAt` provider (default: always true) that `moveTile` checks for
  board targets, so only the village overrides it. Rack size comes from
  `10 + rackBonus` for the village; growing the rack pads `rackCells` with
  empty slots that refill.
- **Words view (`GridBoardView`):** draws fog over unrevealed cells, region
  ground colors, water, fords and special outlines. Visible cells only, as
  today.
- **Village view (`IsoVillageView` / `VillageScene`):** the same layers in
  the angled view, painted only for visible cells.
- **`infinite_estate_screen.dart`:** run counting after each board change
  (next to `_refreshStructures`), the XP float, reward moments for chests,
  shrines and level-ups (`showRewardMoment`), the landing-banner note for
  too-short words (`landingNoteProvider`), the top-bar XP chip, Island map,
  Hint and Compass.

## Commit order (analyze + test before each)

1. `island_map.dart` + tests: regions by distance, wobble stays within ±2,
   level caps, fords exist around the whole river, the same seed always
   gives the same specials, nothing on water.
2. `explore_rules.dart` + tests: required length (highest region, river,
   cap), XP table, first-time bonus, golden double, run keys, reveal
   footprint.
3. Save v3 + migration + tests: a v2 save keeps every letter, reveals
   around them, counts its words, pays no XP.
4. Engine placement guard + rack growth + tests: a drop into fog is
   refused, a pick-up is never refused, a rack of 11 refills.
5. Words view fog/regions/specials rendering.
6. Village view fog/regions/specials rendering.
7. Counting in the village screen: fog lifts, XP float, too-short note,
   chests and golden squares with their moments. Widget test with the fake
   word check.
8. Shrines (Hint, Bigger rack, Compass) + level-up moment + tests.
9. Top bar XP chip + Island map page + test that the village still fits
   at text size 1.15 (411x891).

## Manual check list (on the phone)

1. Open the village: fog lies around your old village, nothing is missing,
   no XP or coins arrive just for opening it.
2. Spell a 3-letter word at the meadow's edge: fog lifts ahead, `+5 XP`
   floats up, the level ring on Me has moved.
3. Try to drop a letter into fog: it bounces back, and Mr. W explains once.
4. Reach a tutorial chest: reward moment, coins, a gold-striped bonus
   letter in the rack.
5. In the Forest, spell a 3-letter word: it stays, but the banner says
   Forest words need 4 letters, and no fog lifts. A 4-letter word lifts it.
6. Golden square: the word's XP is doubled.
7. Find the Hint shrine: Hint button appears; it shows a word that fits.
8. Cross the river at a ford with a short word, and elsewhere with a
   5-letter word.
9. Island map: revealed land, fog, specials, the explored percentage; tap
   to jump.
10. Switch to Sprout (Settings > Word level): no region asks for more than
    4 letters.
11. Switch players on a shared phone: each player has their own fog.
12. Leave and come back: fog, specials, rack size and shrines are all
    still as they were.

## Decisions I guessed (Ryan to confirm)

| # | Guess | Why |
|---|---|---|
| 1 | Fog in 4x4 chunks; a word reveals one chunk ring around each letter | Cheap to save and draw; always some room ahead |
| 2 | You can't drop letters into fog | Makes the fog real; you aim for it |
| 3 | Too-short words stay and still score, they just don't explore | Gentle; nothing you spell is ever "wrong" |
| 4 | Region distances 12 / 30 / 33 / 60 cells | Meadow fits most current villages; each ring takes a few visits |
| 5 | River fords every ~20 cells | Short-word players can always cross |
| 6 | XP goes into the existing level (Me's ring), not a new one | One level is clearer |
| 7 | Shrines: Hint, Bigger rack x2, Compass | New things to unlock; nobody loses features they have today |
| 8 | Chest coins 10/15/25/40 + one bonus letter | Worth reaching, doesn't flood the economy |
| 9 | Boulders with fixed letters and ruins are left for later | They'd need fixed tiles in the engine, which breaks the "connected board" score check |
| 10 | Island map is available from the start, not a shrine | It's how you plan where to go |
