import 'package:flutter/material.dart';
import 'package:namer_app/screens/settings_screen.dart';

import 'game_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        actions: [
            IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                    Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
                }
            )
        ],
      ),
      body: Center(
        child: Column(
          children: [
            const Text('Scrabble',
              style: TextStyle(
                fontSize: 60,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent,
              ),
            ),
            Image.asset('lib_assests/scrabble.jpg',
              width: 600,
              height: 150,
            ),
            OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const GameScreen()),
                  );
                },
                child: const Text('Play'),
            ),
          ],
        )
      ),
    );
  }
}