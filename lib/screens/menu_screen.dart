import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:namer_app/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_screen.dart';
import 'mode_select_screen.dart';

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
      // SingleChildScrollView so adding buttons (Game Modes, and future
      // ones) never overflows on a shorter screen -- it only scrolls if
      // the content actually exceeds the available height.
      body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 60.0),
          child: Column(
            children: [
              //SizedBox(height: 20),
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
                            return FutureBuilder<List<Map<String, dynamic>>>(
                              future: _loadLeaderboardData(), // Function to load data
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return Center(child: CircularProgressIndicator());
                                } else if (snapshot.hasError) {
                                  return Center(child: Text('Error loading data'));
                                } else {
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
                                        for (int i = 0; i < (snapshot.data ?? []).length; i++)
                                          Text('${i + 1}. ${snapshot.data![i]['name']}: ${snapshot.data![i]['displayTime']}',
                                          style: TextStyle(color: Colors.deepPurple),
                                          ),
                                      ],
                                    ),
                                  );
                                }
                              },
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
                    SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ModeSelectScreen()),
                        );
                      },
                      child: const Text('Game Modes',
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

// Entries are stored (in game_screen.dart's winDialog) as JSON objects:
// {"name": ..., "time": <seconds as int>, "displayTime": "MM:SS"}.
// This must decode that same shape rather than treating entries as
// plain "name - time" strings, or parsing silently fails and nothing
// is shown.
Future<List<Map<String, dynamic>>> _loadLeaderboardData() async {
  final prefs = await SharedPreferences.getInstance();
  final entries = prefs.getStringList('leaderboardEntries') ?? [];

  List<Map<String, dynamic>> parsedEntries = entries
      .map((entry) => Map<String, dynamic>.from(jsonDecode(entry) as Map<String, dynamic>))
      .toList();

  // Sort by the stored time in seconds (ascending = fastest time first).
  parsedEntries.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));

  return parsedEntries;
}