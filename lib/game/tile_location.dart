// Identifies one tile slot in a grid game: either a cell on the board or
// a slot in the player's rack. Used as Draggable/DragTarget payload instead
// of the old GlobalKey-per-slot approach, which was needlessly heavy for
// what is really just "which index did this tile come from."
enum TileZone { board, rack }

class TileLocation {
  final TileZone zone;
  final int index;

  const TileLocation(this.zone, this.index);

  @override
  bool operator ==(Object other) =>
      other is TileLocation && other.zone == zone && other.index == index;

  @override
  int get hashCode => Object.hash(zone, index);

  @override
  String toString() => 'TileLocation($zone, $index)';
}
