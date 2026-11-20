// Ready-made names for villagers (spec-16). Kids can type any name instead.

const kVillagerNames = <String>[
  'Pip', 'Moss', 'Juno', 'Wren', 'Fig', 'Bramble', 'Maple', 'Nell', 'Otto', 'Poppy',
  'Basil', 'Clover', 'Dot', 'Elm', 'Finn', 'Hazel', 'Ivy', 'Jasper', 'Kit', 'Lark',
  'Milo', 'Nutmeg', 'Olive', 'Pebble', 'Quill', 'Rosie', 'Sage', 'Tuck', 'Una', 'Willow',
  'Biscuit', 'Cricket', 'Daisy', 'Ember', 'Flint', 'Ginger', 'Heron', 'Juniper', 'Mabel', 'Teddy',
];

const kMaxVillagerNameLength = 12;

/// The ready name and 3 other picks for a villager id: the same every time
/// for the same id, and different between villagers. Names in [taken] are
/// skipped when there are enough others.
List<String> nameChoicesFor(String villagerId, {Set<String> taken = const {}}) {
  var h = 0;
  for (final c in villagerId.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final free = [for (final n in kVillagerNames) if (!taken.contains(n)) n];
  final pool = free.length >= 4 ? free : kVillagerNames;
  final start = h % pool.length;
  return [for (var i = 0; i < 4; i++) pool[(start + i) % pool.length]];
}

/// A typed name, cleaned up: trimmed, spaces squeezed, at most 12 letters.
/// Null if nothing is left (the caller keeps the old name).
String? cleanVillagerName(String typed) {
  var name = typed.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.length > kMaxVillagerNameLength) name = name.substring(0, kMaxVillagerNameLength).trimRight();
  return name.isEmpty ? null : name;
}
