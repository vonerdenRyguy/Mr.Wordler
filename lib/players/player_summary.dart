import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../daily/daily_seed.dart';
import '../portfolio/level_info.dart';
import '../settings/word_level.dart';
import '../ui/tokens.dart';
import 'players.dart';

/// What the "Who's playing?" and Family screens show about a player,
/// read straight from that player's saves (they may not be the one
/// holding the phone, so their controllers aren't loaded).
class PlayerSummary {
  const PlayerSummary({
    required this.level,
    required this.portfolioLevel,
    required this.coins,
    required this.playedToday,
    required this.journal,
  });

  final WordLevel level;
  final int portfolioLevel;
  final int coins;
  final bool playedToday;

  /// Magic words discovered in their village.
  final int journal;

  static Future<PlayerSummary> load(Player player, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> json(String key) {
      try {
        final raw = prefs.getString('${player.prefix}$key');
        return raw == null ? const {} : jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return const {};
      }
    }

    final portfolio = json('portfolioData');
    final daily = json('dailyChallengeData');
    final village = json('infiniteEstateVillageSave');
    return PlayerSummary(
      level: wordLevelFromName(prefs.getString('${player.prefix}wordLevel')) ?? WordLevel.wordsmith,
      portfolioLevel: levelInfoForXp(portfolio['totalXp'] as int? ?? 0).level,
      coins: portfolio['currency'] as int? ?? 0,
      playedToday: daily['lastPlayedDateKey'] == dailyDateKey(now),
      journal: (village['discoveredWords'] as List?)?.length ?? 0,
    );
  }
}

/// A player's round badge: their color with their initial.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.player, this.size = 36});

  final Player player;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: player.color,
          shape: BoxShape.circle,
          border: Border.all(color: WColors.ink, width: size >= 60 ? WSize.outline : WSize.outlineSmall),
        ),
        child: Text(
          player.initial,
          textScaler: TextScaler.noScaling,
          style: TextStyle(fontFamily: WFonts.display, fontSize: size * 0.55, color: WColors.ink, height: 1.0),
        ),
      ),
    );
  }
}
