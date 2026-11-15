import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/word_level.dart';
import '../ui/tokens.dart';

// A family on one phone (spec-07): several players share the app, each
// with their own village, coins, Portfolio, stats, Daily and word level.
//
// How the saves are kept apart: every per-player save key gets the
// player's prefix in front (see PlayerKeys). The first player's prefix is
// empty, so the save that existed before spec-07 simply *is* player one --
// nothing is moved or rewritten. Text size, Reduce motion, dark mode and
// the definition cache stay shared by the whole phone.

const kFirstPlayerId = 'p1';
const kMaxPlayers = 6;

/// The colors a player can pick, by index.
const kPlayerColors = <Color>[WColors.sun, WColors.sky, WColors.coral, WColors.leaf, WColors.lilac, WColors.white];

class Player {
  const Player({required this.id, required this.name, required this.colorIndex});

  final String id;
  final String name;
  final int colorIndex;

  Color get color => kPlayerColors[colorIndex % kPlayerColors.length];
  String get initial => name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

  /// What goes in front of this player's save keys.
  String get prefix => id == kFirstPlayerId ? '' : '${id}_';

  Player copyWith({String? name, int? colorIndex}) =>
      Player(id: id, name: name ?? this.name, colorIndex: colorIndex ?? this.colorIndex);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'colorIndex': colorIndex};

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Player',
        colorIndex: json['colorIndex'] as int? ?? 0,
      );
}

/// The save-key prefix of the player currently holding the phone. Each
/// per-player controller reads it once, when it is created, and keeps it,
/// so a save still in flight when players switch lands in the right place.
class PlayerKeys {
  static String prefix = '';

  static String of(String key) => '$prefix$key';
}

class PlayersState {
  const PlayersState({required this.players, required this.currentId, this.nextNumber = 2});

  final List<Player> players;
  final String currentId;
  final int nextNumber;

  static const initial = PlayersState(
    players: [Player(id: kFirstPlayerId, name: 'Me', colorIndex: 0)],
    currentId: kFirstPlayerId,
  );

  Player get current => players.firstWhere((p) => p.id == currentId, orElse: () => players.first);

  /// Two or more players: the family features switch on.
  bool get isFamily => players.length >= 2;
  bool get canAdd => players.length < kMaxPlayers;

  Player? byId(String id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class PlayersController extends StateNotifier<PlayersState> {
  PlayersController() : super(PlayersState.initial) {
    _ready = _load();
  }

  static const prefsKey = 'playersData';
  late final Future<void> _ready;

  /// Completes once the saved players have been read.
  Future<void> get ready => _ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || !mounted) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final players = [for (final p in json['players'] as List) Player.fromJson(p as Map<String, dynamic>)];
      if (players.isEmpty) return;
      final loaded = PlayersState(
        players: players,
        currentId: json['currentId'] as String? ?? players.first.id,
        nextNumber: json['nextNumber'] as int? ?? players.length + 1,
      );
      PlayerKeys.prefix = loaded.current.prefix;
      state = loaded;
    } catch (_) {
      // Corrupt data -- carry on with the one player the phone always has.
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode({
        'players': [for (final p in state.players) p.toJson()],
        'currentId': state.currentId,
        'nextNumber': state.nextNumber,
      }),
    );
  }

  /// Adds a player with their own (empty) saves and word level. Null when
  /// the phone already has kMaxPlayers.
  Future<Player?> add({required String name, required int colorIndex, required WordLevel level}) async {
    if (!state.canAdd) return null;
    final player = Player(id: 'p${state.nextNumber}', name: name.trim(), colorIndex: colorIndex);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${player.prefix}wordLevel', level.name);
    state = PlayersState(
      players: [...state.players, player],
      currentId: state.currentId,
      nextNumber: state.nextNumber + 1,
    );
    await _save();
    return player;
  }

  Future<void> update(String id, {String? name, int? colorIndex}) async {
    state = PlayersState(
      players: [
        for (final p in state.players)
          if (p.id == id) p.copyWith(name: name?.trim(), colorIndex: colorIndex) else p,
      ],
      currentId: state.currentId,
      nextNumber: state.nextNumber,
    );
    await _save();
  }

  /// Hands the phone to [id]: every per-player provider reloads from that
  /// player's saves.
  Future<void> select(String id) async {
    final player = state.byId(id);
    if (player == null || id == state.currentId) return;
    PlayerKeys.prefix = player.prefix;
    state = PlayersState(players: state.players, currentId: id, nextNumber: state.nextNumber);
    await _save();
  }
}

final playersProvider = StateNotifierProvider<PlayersController, PlayersState>((ref) {
  ref.onDispose(() => PlayerKeys.prefix = '');
  return PlayersController();
});

/// Watched by every per-player provider, so it is rebuilt (and reloads)
/// when the phone changes hands.
final currentPlayerIdProvider = Provider<String>((ref) => ref.watch(playersProvider.select((s) => s.currentId)));
