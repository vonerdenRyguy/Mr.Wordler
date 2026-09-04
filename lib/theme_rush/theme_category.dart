// A themed word category for Theme Rush. `words` are the words that count
// as satisfying the theme -- checked against words the shared word
// validator finds on the board, not against the dictionary itself (a
// dictionary word can be perfectly valid without matching a theme).
class ThemeCategory {
  final String id;
  final String name;
  final Set<String> words; // uppercase

  const ThemeCategory({required this.id, required this.name, required this.words});
}

const List<ThemeCategory> kThemeCategories = [
  ThemeCategory(
    id: 'animals',
    name: 'Animals',
    words: {
      'CAT', 'DOG', 'LION', 'TIGER', 'BEAR', 'WOLF', 'FOX', 'DEER', 'GOAT',
      'SHEEP', 'HORSE', 'MOUSE', 'RAT', 'BAT', 'OWL', 'HAWK', 'CROW', 'DUCK',
      'SWAN', 'FROG', 'TOAD', 'SNAKE', 'SHARK', 'WHALE', 'SEAL', 'CRAB',
      'ANT', 'BEE', 'WASP', 'MOTH', 'GOOSE', 'HEN', 'PIG', 'COW', 'OX',
      'MULE', 'HARE', 'MOLE', 'LYNX', 'PUMA', 'CAMEL', 'ZEBRA', 'MONKEY',
      'EAGLE', 'ROBIN', 'FINCH', 'SQUID', 'CLAM', 'SNAIL', 'WORM',
    },
  ),
  ThemeCategory(
    id: 'food',
    name: 'Food',
    words: {
      'BREAD', 'RICE', 'MEAT', 'FISH', 'EGG', 'MILK', 'CHEESE', 'APPLE',
      'GRAPE', 'LEMON', 'PEACH', 'PEAR', 'PLUM', 'BEAN', 'CORN', 'SOUP',
      'CAKE', 'PIE', 'STEW', 'TACO', 'SUSHI', 'PASTA', 'SALAD', 'STEAK',
      'BACON', 'HONEY', 'SUGAR', 'SALT', 'BUTTER', 'CREAM', 'JUICE', 'TEA',
      'COFFEE', 'MANGO', 'MELON', 'ONION', 'GARLIC', 'PEPPER', 'OLIVE',
      'NUT', 'OAT', 'YAM', 'FIG', 'DATE', 'LIME', 'BERRY', 'TOAST',
    },
  ),
  ThemeCategory(
    id: 'countries',
    name: 'Countries',
    words: {
      'CHINA', 'INDIA', 'JAPAN', 'SPAIN', 'ITALY', 'FRANCE', 'EGYPT',
      'KENYA', 'CHILE', 'PERU', 'CUBA', 'HAITI', 'GHANA', 'LIBYA', 'SYRIA',
      'YEMEN', 'QATAR', 'OMAN', 'LAOS', 'NEPAL', 'ISRAEL', 'JORDAN',
      'RUSSIA', 'GREECE', 'POLAND', 'NORWAY', 'SWEDEN', 'FINLAND', 'CANADA',
      'MEXICO', 'BRAZIL', 'PANAMA', 'MALI', 'CHAD', 'TOGO', 'BENIN',
      'GABON', 'SUDAN', 'ANGOLA', 'ZAMBIA', 'MALAWI', 'UGANDA',
    },
  ),
];
