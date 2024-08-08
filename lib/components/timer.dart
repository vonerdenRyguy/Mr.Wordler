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