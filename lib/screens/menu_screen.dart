import 'package:flutter/material.dart';
import 'package:namer_app/screens/settings_screen.dart';

import 'game_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        //title: const Text('Menu'),
        actions: [
            IconButton(
                icon: const Icon(Icons.settings, color: Colors.black),
                onPressed: () {
                    Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
                }
            )
        ],
        backgroundColor: Colors.deepPurple,
      ),
      backgroundColor: Colors.orangeAccent,
      body: Center(
        child: Padding(padding: EdgeInsets.only(top: 100.0),
          child: Column(
            //mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(height: 30),
              Text('Mr. Wordler',
                style: TextStyle(
                  fontSize: 60,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.deepPurple,
                  decorationThickness: 1.5,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              SizedBox(height: 15),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.deepPurple,
                    width: 3.0
                  ),
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20.0),
                  child: Image.asset(
                    'lib_assests/scrabble.jpg',
                    height: 193,
                  ),
                ),
              ),
              SizedBox(height: 20),
              Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.deepPurple, width: 3.0),
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                padding: EdgeInsets.symmetric(horizontal: 90.0),
                child: Column(
                  children: [
                    OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const GameScreen()),
                          );
                        },
                        child: Text('Play',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                    ),
                    SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              backgroundColor: Colors.orangeAccent,
                              title: Center(
                                child: Text('Top Times',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple,
                                  ),
                                ),
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Add content to your AlertDialog here
                                ],
                              ),
                            );
                          },
                        );
                      },
                      child: const Text('Leaderboard',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ], // Children
          )
        ),
      ),
    );
  }
}