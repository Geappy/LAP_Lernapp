// lib/util/app_dirs_stub.dart
abstract class AppDirs {
  /// Auf Mobile/Desktop: Pfad zu App-Dokumenten.
  /// Auf Web: null.
  static Future<String?> documentsPath() => Future.value(null);
}
