// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/decks_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Fullscreen: hide both status bar & navigation bar, auto-hide after swipe.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const KartenApp());
}

class KartenApp extends StatelessWidget {
  const KartenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Optionally set overlay style for when bars briefly appear
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, // draw behind status bar
      statusBarIconBrightness: Brightness.light, // Android
      statusBarBrightness: Brightness.dark,      // iOS
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return const _FullscreenReapplicator(
      child: MaterialApp(
        title: 'Karteikarten',
        debugShowCheckedModeBanner: false,
        home: DecksScreen(),
      ),
    );
  }
}

/// Some Android OEMs re-show system UI when app resumes.
/// This widget reapplies the immersive mode on resume.
class _FullscreenReapplicator extends StatefulWidget {
  const _FullscreenReapplicator({required this.child, super.key});
  final Widget child;

  @override
  State<_FullscreenReapplicator> createState() => _FullscreenReapplicatorState();
}

class _FullscreenReapplicatorState extends State<_FullscreenReapplicator>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyFullscreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyFullscreen();
    }
  }

  void _applyFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
