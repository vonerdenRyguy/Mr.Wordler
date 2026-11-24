// A made-up village with 366 letters and 15 buildings, for tests and pictures.
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/planet.dart';

const _row = 334, _col = 224;
const _rows = [
  '................................T......',
  '................................I......',
  '.................H..G...L.......G......',
  '...............BOAT.APPLE...MOTHER.....',
  '.................R..R...MILL.T..R.....S',
  '.................B..D...O....T........U',
  '..........P.....HOUSE.SUNSHINE........M',
  '..........I......R..N........R........M',
  '..........C.........E.B..S........WHALE',
  '..........N.......STREAM.T..O.P...E...R',
  '..........I.G.........R..O..R.I.WELL...',
  '.........OCEAN.....THUNDER..C.L.A.L....',
  '............R.......O....I..H.L.G......',
  '............D....G..N....E..A.O.O.H....',
  '......K.....E...BASKET.SISTER.WINDOW...',
  '....P.E.ISLAND.B.R..Y.....R.D.....U....',
  '....E.T..A....LADDER......A.....U.S....',
  '....AUTUMN..S..R.E......E.I.T.DANCER...',
  '....C.L..DOLPHIN.N.....RAINBOW..C......',
  '....H.E.....R.........F.G...W...L......',
  '.WAVE.......I........SAIL..TEACHER.....',
  '..N.S...FRIEND......P.R.E...R..O.......',
  '..C......A..G......FARM.......BRIDGE...',
  '..H...CRAB..........I..........S.......',
  'CLOUD....B.T......PANDA.......PEBBLE...',
  '..R......I.U........T...........L......',
  '......WINTER...M.TOWER...F...MELON.....',
  '...........T...E.A..R..C.O..B...S..S...',
  '...........L...A.B.....A.R.HARVEST.H...',
  '........KITE...D.LANTERN.E..D...O..E...',
  '.............STONE.....D.SINGER.MILL...',
  '...............W.......L.T..E......L...',
  '....................RIVER.CURTAIN......',
];

/// Board cell -> letter; every run is a real word.
Map<int, String> closeUpTestLetters() => {
      for (var r = 0; r < _rows.length; r++)
        for (var c = 0; c < _rows[r].length; c++)
          if (_rows[r][c] != '.') (_row + r) * kPlanetBoard + _col + c: _rows[r][c],
    };

/// That village as the planet draws it.
List<GlobeVillage> bigTestVillage() {
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
