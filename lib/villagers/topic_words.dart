// Topic word lists for villager wishes (spec-16). The dictionary has no
// topics, so these ship with the app; no internet needed. A word counts for
// a topic wish only if it is in the list AND the real dictionary accepted it
// as a word on the board. test/villagers_test.dart checks every word against
// the dictionary file and the list sizes.

class Topic {
  const Topic(this.id, this.title, this.ask, this.words);

  final String id;
  final String title;

  /// What the villager says: "wishes for ...".
  final String ask;

  /// UPPER-CASE words, 3+ letters.
  final List<String> words;

  /// The short words (3-4 letters) Sprout players are asked for.
  List<String> get shortWords => [for (final w in words) if (w.length <= 4) w];

  bool hasWord(String word) => words.contains(word.toUpperCase());
}

const kTopics = <Topic>[
  Topic('animals', 'Animals', 'an animal', [
    'CAT', 'DOG', 'COW', 'PIG', 'HEN', 'FOX', 'OWL', 'BEE', 'ANT', 'BAT', 'RAT', 'APE', 'EEL', 'ELK', 'YAK',
    'LION', 'BEAR', 'DUCK', 'FROG', 'GOAT', 'DEER', 'WOLF', 'CRAB', 'FISH', 'BIRD', 'MOTH', 'SEAL', 'SWAN', 'TOAD', 'LAMB',
    'HORSE', 'MOUSE', 'SHEEP', 'ZEBRA', 'TIGER', 'EAGLE', 'SNAKE', 'WHALE', 'OTTER', 'BISON', 'ROBIN', 'HIPPO', 'PANDA', 'KOALA',
    'RABBIT', 'TURTLE', 'MONKEY', 'DONKEY', 'BEETLE', 'SPIDER', 'PARROT', 'DOLPHIN', 'GIRAFFE', 'PENGUIN', 'CHICKEN', 'LIZARD',
  ]),
  Topic('food', 'Food', 'something to eat', [
    'PIE', 'JAM', 'EGG', 'HAM', 'NUT', 'BUN', 'FIG', 'PEA', 'YAM',
    'CAKE', 'BEAN', 'RICE', 'SOUP', 'MEAT', 'CORN', 'PEAR', 'PLUM', 'LIME', 'KALE', 'TACO', 'TOFU', 'MILK', 'FISH', 'OATS',
    'APPLE', 'BREAD', 'PIZZA', 'PASTA', 'LEMON', 'GRAPE', 'HONEY', 'BACON', 'CANDY', 'PEACH', 'MANGO', 'ONION', 'SALAD', 'TOAST', 'CREAM',
    'BANANA', 'CHEESE', 'COOKIE', 'CARROT', 'ORANGE', 'POTATO', 'PEPPER', 'BUTTER', 'NOODLE', 'WAFFLE', 'PEANUT', 'SANDWICH', 'PANCAKE',
  ]),
  Topic('water', 'Water', 'a word about water', [
    'SEA', 'ICE', 'WET', 'FOG', 'DEW', 'BAY',
    'TIDE', 'RAIN', 'POND', 'LAKE', 'POOL', 'WAVE', 'SWIM', 'BOAT', 'DIVE', 'DROP', 'MIST', 'SURF', 'SALT',
    'RIVER', 'OCEAN', 'BEACH', 'SHORE', 'CREEK', 'FLOAT', 'STORM', 'WATER', 'STEAM', 'WHALE', 'CORAL', 'SWAMP', 'FLOOD',
    'ISLAND', 'STREAM', 'PUDDLE', 'SAILOR', 'HARBOR', 'SPLASH', 'BUBBLE', 'CURRENT', 'FOUNTAIN', 'WATERFALL',
  ]),
  Topic('weather', 'Weather', 'a word about weather', [
    'SUN', 'FOG', 'ICE', 'WET', 'DEW', 'ICY',
    'RAIN', 'SNOW', 'WIND', 'HAIL', 'MIST', 'WARM', 'COLD', 'HEAT', 'COOL', 'GALE', 'HAZE',
    'FROST', 'STORM', 'CLOUD', 'CLEAR', 'SUNNY', 'WINDY', 'RAINY', 'FOGGY', 'CHILL', 'FLOOD', 'SNOWY',
    'FREEZE', 'BREEZE', 'SHOWER', 'CLOUDY', 'WINTER', 'SUMMER', 'SPRING', 'AUTUMN', 'SEASON',
    'THUNDER', 'DRIZZLE', 'RAINBOW', 'TORNADO', 'BLIZZARD', 'LIGHTNING',
  ]),
  Topic('home', 'Home', 'something in a home', [
    'BED', 'CUP', 'RUG', 'TUB', 'PAN', 'POT', 'FAN', 'BOX', 'KEY', 'MAT', 'MUG',
    'LAMP', 'DOOR', 'SOFA', 'DESK', 'ROOF', 'WALL', 'SINK', 'BATH', 'OVEN', 'FORK',
    'SPOON', 'TABLE', 'CHAIR', 'CLOCK', 'STOVE', 'SHELF', 'FLOOR', 'PLATE', 'BROOM', 'COUCH', 'PORCH', 'ATTIC',
    'WINDOW', 'KITCHEN', 'PILLOW', 'CARPET', 'GARDEN', 'MIRROR', 'BEDROOM', 'CURTAIN', 'CABINET', 'TOASTER', 'BLANKET', 'STAIRS', 'BASEMENT',
  ]),
  Topic('plants', 'Plants', 'a plant', [
    'OAK', 'FIR', 'IVY', 'LILY', 'FERN', 'ROSE', 'MOSS', 'TREE', 'SEED', 'ROOT', 'LEAF', 'BUSH', 'WEED', 'BARK', 'VINE', 'REED', 'PALM', 'PINE', 'STEM',
    'DAISY', 'TULIP', 'BLOOM', 'GRASS', 'BIRCH', 'MAPLE', 'PETAL', 'BERRY', 'POPPY', 'SHRUB', 'HEDGE', 'ACORN',
    'CLOVER', 'CACTUS', 'FLOWER', 'SPROUT', 'ORCHID', 'WILLOW', 'BAMBOO', 'MEADOW', 'FOREST', 'BRANCH',
    'BLOSSOM', 'THISTLE', 'SUNFLOWER',
  ]),
  Topic('colors', 'Colors', 'a color', [
    'RED', 'TAN', 'BLUE', 'PINK', 'GRAY', 'GREY', 'GOLD', 'JADE', 'ROSE', 'LIME', 'NAVY', 'PLUM', 'RUST', 'TEAL',
    'GREEN', 'BLACK', 'WHITE', 'BROWN', 'CREAM', 'IVORY', 'LILAC', 'AMBER', 'CORAL', 'OLIVE', 'PEACH', 'LEMON', 'MAUVE', 'SILVER', 'BEIGE', 'KHAKI',
    'ORANGE', 'YELLOW', 'PURPLE', 'VIOLET', 'INDIGO', 'MAROON', 'COPPER', 'BRONZE',
    'CRIMSON', 'SCARLET', 'MAGENTA', 'TURQUOISE',
  ]),
  Topic('move', 'Things that move', 'something that moves', [
    'CAR', 'BUS', 'VAN', 'JET', 'CAB', 'SUB', 'RUN', 'HOP', 'FLY',
    'BIKE', 'BOAT', 'SHIP', 'SLED', 'CART', 'TRAM', 'TAXI', 'RAFT', 'SKIP', 'JUMP', 'WALK', 'SWIM', 'ROLL', 'SPIN', 'SAIL',
    'TRAIN', 'TRUCK', 'PLANE', 'SKATE', 'WAGON', 'CANOE', 'FERRY', 'KAYAK', 'SLIDE', 'CLIMB', 'DANCE', 'CRAWL', 'FLOAT',
    'SCOOTER', 'ROCKET', 'TRACTOR', 'GALLOP', 'SUBWAY', 'ESCALATOR', 'ELEVATOR', 'HELICOPTER',
  ]),
];

Topic topicById(String id) => kTopics.firstWhere((t) => t.id == id);
