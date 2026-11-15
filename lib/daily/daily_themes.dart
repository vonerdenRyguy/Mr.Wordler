// The Daily puzzle's themes (spec-05). Each day has one theme and one
// secret word from it (see daily_puzzle.dart). Every word is 4-6 letters,
// in the game dictionary, in exactly one theme, and never a magic word --
// test/daily_themes_test.dart checks all of that.
class DailyTheme {
  final String id;
  final String name;
  final List<String> words; // uppercase

  const DailyTheme({required this.id, required this.name, required this.words});
}

const List<DailyTheme> kDailyThemes = [
  DailyTheme(id: 'animals', name: 'Animals', words: [
    'HORSE', 'TIGER', 'SHEEP', 'MOUSE', 'WHALE', 'SNAKE', 'EAGLE', 'ZEBRA',
    'CAMEL', 'GOOSE', 'ROBIN', 'SNAIL', 'SHARK', 'OTTER', 'RABBIT', 'DONKEY',
  ]),
  DailyTheme(id: 'food', name: 'Food', words: [
    'BREAD', 'APPLE', 'GRAPE', 'LEMON', 'PEACH', 'PASTA', 'SALAD', 'HONEY',
    'CHEESE', 'BUTTER', 'TOAST', 'MELON', 'ONION', 'BERRY', 'CREAM', 'CARROT',
  ]),
  DailyTheme(id: 'garden', name: 'In the garden', words: [
    'ROSE', 'SEED', 'LEAF', 'STEM', 'PETAL', 'BLOOM', 'GRASS', 'HEDGE',
    'FENCE', 'SPADE', 'MULCH', 'CLOVER', 'VIOLET', 'TULIP', 'DAISY', 'ORCHID',
  ]),
  DailyTheme(id: 'weather', name: 'Weather', words: [
    'RAIN', 'SNOW', 'WIND', 'CLOUD', 'STORM', 'SUNNY', 'FROST', 'BREEZE',
    'MISTY', 'SLEET', 'FOGGY', 'HAIL', 'SHOWER', 'CHILLY', 'HUMID', 'WINTER',
  ]),
  DailyTheme(id: 'home', name: 'Around the house', words: [
    'TABLE', 'CHAIR', 'COUCH', 'SHELF', 'STOVE', 'CLOCK', 'LAMP', 'QUILT',
    'PILLOW', 'MIRROR', 'CARPET', 'WINDOW', 'DOOR', 'PORCH', 'STAIRS', 'CLOSET',
  ]),
  DailyTheme(id: 'music', name: 'Music', words: [
    'PIANO', 'FLUTE', 'DRUMS', 'VIOLIN', 'GUITAR', 'BANJO', 'CHOIR', 'TEMPO',
    'CHORD', 'MELODY', 'SONG', 'TUNE', 'OPERA', 'WALTZ', 'BUGLE', 'CELLO',
  ]),
  DailyTheme(id: 'clothes', name: 'Clothes', words: [
    'SHIRT', 'SKIRT', 'SCARF', 'GLOVE', 'SOCKS', 'DRESS', 'JACKET', 'BOOTS',
    'APRON', 'SHAWL', 'COAT', 'VEST', 'BELT', 'SHOES', 'MITTEN', 'SANDAL',
  ]),
  DailyTheme(id: 'sea', name: 'By the sea', words: [
    'OCEAN', 'BEACH', 'SHELL', 'CORAL', 'WAVES', 'TIDE', 'SAND', 'BOAT',
    'ANCHOR', 'HARBOR', 'PEARL', 'SHORE', 'GULL', 'DOCK', 'KELP', 'SAILOR',
  ]),
];
