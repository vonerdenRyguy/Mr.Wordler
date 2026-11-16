import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../daily/daily_seed.dart';

// Mr. W's tips on Home (spec-11): at most one short tip on a page, and
// only when it would help.

/// The three Home pages, left to right.
enum HomePage { me, play, family }

class HomeTip {
  const HomeTip(this.id, this.text);

  /// Stable for the day, so the X can hide it.
  final String id;
  final String text;
}

/// What the tips look at.
class TipFacts {
  const TipFacts({
    required this.playedToday,
    required this.buildings,
    required this.waitingFromFamily,
    required this.hasFamily,
    required this.familyWordSolved,
    required this.wordOfDayClaimed,
    this.askerName,
    this.askedLetter,
  });

  final bool playedToday;

  /// Buildings in your village; null while it loads.
  final int? buildings;

  /// Gifts, cheers and requests from the online family.
  final int waitingFromFamily;
  final bool hasFamily;
  final bool familyWordSolved;
  final bool wordOfDayClaimed;

  /// Someone in the family who asked for a letter today.
  final String? askerName;
  final String? askedLetter;
}

String _a(String letter) => 'AEFHILMNORSX'.contains(letter) ? 'an' : 'a';

/// The tip for [page], or null when there's nothing worth saying.
HomeTip? homeTipFor(HomePage page, TipFacts f) {
  switch (page) {
    case HomePage.play:
      if (f.waitingFromFamily > 0) {
        return const HomeTip('family-waiting', 'Your family sent you something. Swipe to see it \u{1F449}');
      }
      if (!f.playedToday) return const HomeTip('daily', "Try today's Daily puzzle. There's a new one every day!");
      if (f.buildings == 0) {
        return const HomeTip('first-building', 'Visit your village and spell FARM to raise your first building.');
      }
      return null;
    case HomePage.family:
      if (f.askerName != null && f.askedLetter != null) {
        return HomeTip('ask-${f.askedLetter}',
            '${f.askerName} needs ${_a(f.askedLetter!)} ${f.askedLetter}. Tap Send to help.');
      }
      if (f.hasFamily && !f.familyWordSolved && !f.playedToday) {
        return const HomeTip('family-word', 'Play the Daily puzzle to find your family-word letters.');
      }
      return null;
    case HomePage.me:
      if (!f.wordOfDayClaimed) return const HomeTip('word-of-day', "Spell the word of the day in your village for +10 coins.");
      return null;
  }
}

/// Tips hidden with the X today. Per phone; forgotten tomorrow.
class HiddenTipsController extends StateNotifier<Set<String>> {
  HiddenTipsController({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const {}) {
    _load();
  }

  static const prefsKey = 'hiddenTips';
  final DateTime Function() _now;

  String get _today => dailyDateKey(_now());

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || !mounted) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['day'] == _today) {
        state = {...state, for (final id in (json['ids'] as List? ?? const [])) id as String};
      }
    } catch (_) {
      // A bad value just means nothing is hidden.
    }
  }

  Future<void> hide(String id) async {
    state = {...state, id};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode({'day': _today, 'ids': state.toList()}));
  }
}

final hiddenTipsProvider = StateNotifierProvider<HiddenTipsController, Set<String>>((ref) => HiddenTipsController());
