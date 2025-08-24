import 'package:flutter/material.dart';
import 'ui/decks_screen.dart';

void main() => runApp(const LernkartenApp());

class LernkartenApp extends StatelessWidget {
  const LernkartenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karteikarten',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const DecksScreen(),
    );
  }
}
