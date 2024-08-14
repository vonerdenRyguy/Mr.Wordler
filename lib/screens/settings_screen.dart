import 'dart:math';

import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _RandomPositionButtonState();
}

class _RandomPositionButtonState extends State<SettingsScreen> {
  Offset _buttonPosition = const Offset(50, 100); // Initial position
  final _random = Random();

  void _moveButton() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const buttonWidth = 100.0; // Adjust as needed
    const buttonHeight = 50.0; // Adjust as needed

    setState(() {
      _buttonPosition = Offset(
        _random.nextDouble() * (screenWidth - buttonWidth),
        _random.nextDouble() * (screenHeight - buttonHeight),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Other widgets in your layout...

        Positioned(
          left: _buttonPosition.dx,
          top: _buttonPosition.dy,
          child: IconButton(
            iconSize: 50.0,
            icon: const Icon(Icons.accessible_forward_sharp, color: Colors.pinkAccent),
            onPressed: _moveButton,
          ),
        ),
      ],
    );
  }
}