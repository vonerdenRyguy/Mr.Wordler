import 'dart:math';

import 'package:flutter/material.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';

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
    final themeNotifier = context.watch<ThemeNotifier>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.deepPurple,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  SwitchListTile(
                    title: const Text('Dark Mode'),
                    value: themeNotifier.isDarkMode,
                    onChanged: (value) => themeNotifier.setDarkMode(value),
                  ),
                ],
              ),
              // Easter egg: the settings icon runs away when you try to
              // press it.
              Positioned(
                left: _buttonPosition.dx,
                top: _buttonPosition.dy,
                child: IconButton(
                  iconSize: _buttonSize - 10,
                  icon: const Icon(Icons.accessible_forward_sharp, color: Colors.pinkAccent),
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
