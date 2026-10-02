import 'dart:math';

import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import '../ui/wordler_scaffold.dart';

// The Dark Mode switch is hidden for now: the app's look is light only
// until a proper dark palette exists. ThemeNotifier and its saved value
// are kept as they are, so nothing is lost when the switch comes back.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Offset _buttonPosition = const Offset(50, 100);
  final _random = Random();
  static const double _buttonSize = 60.0;

  void _moveButton(BoxConstraints constraints) {
    final maxX = (constraints.maxWidth - _buttonSize).clamp(0.0, double.infinity);
    final maxY = (constraints.maxHeight - _buttonSize).clamp(0.0, double.infinity);
    setState(() {
      _buttonPosition = Offset(
        _random.nextDouble() * maxX,
        _random.nextDouble() * maxY,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return WordlerScaffold(
      title: 'Settings',
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              const Padding(
                padding: EdgeInsets.all(WSize.screenPadding),
                child: Text('Nothing to change here yet.', style: WText.label),
              ),
              // Easter egg: this button runs away when you try to press it.
              Positioned(
                left: _buttonPosition.dx,
                top: _buttonPosition.dy,
                child: IconButton(
                  iconSize: _buttonSize - 10,
                  icon: const Icon(Icons.accessible_forward_sharp, color: WColors.coral),
                  onPressed: () => _moveButton(constraints),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
