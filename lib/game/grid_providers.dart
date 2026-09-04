import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'grid_config.dart';
import 'grid_game_controller.dart';
import 'grid_game_state.dart';

// Each mode screen wraps its content in its own `ProviderScope(overrides:
// [gridConfigProvider.overrideWithValue(...)])` so every mode gets a fresh,
// independently-configured game (different board/rack size, seed, refill
// behavior) while sharing this exact controller/provider wiring. Throwing
// when unoverridden makes a missing override fail loudly instead of
// silently sharing state across modes.
final gridConfigProvider = Provider<GridConfig>((ref) {
  throw UnimplementedError(
      'gridConfigProvider must be overridden per mode screen');
});

final gridGameControllerProvider =
    StateNotifierProvider.autoDispose<GridGameController, GridGameState>((ref) {
  final config = ref.watch(gridConfigProvider);
  return GridGameController(config);
});
