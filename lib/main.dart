import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/screens/menu_screen.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Bananagrams',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: const MenuScreen(),
    );
  }
}

