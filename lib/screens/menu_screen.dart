import 'package:flutter/material.dart';
import 'package:namer_app/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
                                          Text('${i + 1}. ${snapshot.data![i]['name']}: ${snapshot.data![i]['time']}'),
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

Future<List<Map<String, dynamic>>> _loadLeaderboardData() async {
  final prefs = await SharedPreferences.getInstance();
  final entries = prefs.getStringList('leaderboardEntries') ?? [];

  List<Map<String, dynamic>> parsedEntries = [];
  for (String entry in entries) {
    final parts = entry.split(' - ');
    if (parts.length == 2) {
      parsedEntries.add({
        'name': parts[0],
        'time': parts[1],
        'totalTimeInSeconds': _timeToSeconds(parts[1]), // Calculate total seconds
      });
    }
  }

  // Sort entries based on totalTimeInSeconds (ascending order for shortest time first)
  parsedEntries.sort((a, b) {
    return (a['totalTimeInSeconds'] as int).compareTo(b['totalTimeInSeconds'] as int);
  });

  return parsedEntries;
}

// Helper function to convert "hr:min:sec" to total seconds
int _timeToSeconds(String timeString) {
  final parts = timeString.split(':').map((s) => int.tryParse(s) ?? 0).toList();
  if (parts.length == 3) {
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
  }
  return 0;
}