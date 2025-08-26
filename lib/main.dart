// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/decks_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Vollbild (Leisten blenden nach Wisch kurz ein und wieder aus)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const KartenApp());
}

class KartenApp extends StatelessWidget {
  const KartenApp({super.key});

  // Akzentfarbe nach Wunsch anpassen
  static const Color _seed = Color(0xFF5B7CFA);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karteikarten',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
      ),
      home: const DecksScreen(),
    );
  }
}
