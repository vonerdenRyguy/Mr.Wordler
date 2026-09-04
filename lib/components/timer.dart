import 'dart:async';
import 'package:flutter/material.dart';

class StopwatchManager {
  final Stopwatch _stopwatch = Stopwatch();
  late Timer? _timer;
  String elapsedTime = '00:00';

  StopwatchManager(this._buildContext);
  final BuildContext _buildContext;

  void start() {
    _stopwatch.start();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      // If the screen that owns this context has been popped (e.g. the
      // player exited without winning), the element is no longer mounted.
      // Calling markNeedsBuild on it throws, so stop the timer instead.
      if (!_buildContext.mounted) {
        timer.cancel();
        return;
      }
      elapsedTime = _formatElapsedTime(_stopwatch.elapsed);
      (_buildContext as Element).markNeedsBuild();
    });
  }

  void stop() {
    _stopwatch.stop();
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    _stopwatch.reset();
    elapsedTime = '00:00';
  }

  String _formatElapsedTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  String getElapsedTime() {
    return elapsedTime;
  }
}

// Counts down from `duration` to zero, calling `onExpired` once when it
// hits zero. Used by Time Attack (and any other timed mode). Mirrors
// StopwatchManager's context-mounted guard for the same reason: the timer
// must not touch a disposed screen's Element after the player navigates
// away before time runs out.
class CountdownManager {
  CountdownManager(this._buildContext, {required Duration duration, this.onExpired})
      : _remaining = duration;

  final BuildContext _buildContext;
  final VoidCallback? onExpired;
  Duration _remaining;
  Timer? _timer;
  bool _expiredCalled = false;

  String get remainingTime => _formatDuration(_remaining);
  bool get isExpired => _remaining <= Duration.zero;

  void start() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_buildContext.mounted) {
        timer.cancel();
        return;
      }
      _remaining -= const Duration(seconds: 1);
      if (_remaining <= Duration.zero) {
        _remaining = Duration.zero;
        timer.cancel();
      }
      (_buildContext as Element).markNeedsBuild();
      if (_remaining <= Duration.zero && !_expiredCalled) {
        _expiredCalled = true;
        onExpired?.call();
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }
}