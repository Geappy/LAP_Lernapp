import 'package:flutter/material.dart';
import 'ui/decks_screen.dart';

void main() {
  runApp(const KartenApp());
}

class KartenApp extends StatelessWidget {
  const KartenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karteikarten',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2F7DDE),
        useMaterial3: true,
      ),
      home: const DecksScreen(),
    );
  }
}
