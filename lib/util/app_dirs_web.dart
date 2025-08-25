// lib/util/app_dirs_web.dart
import 'app_dirs_stub.dart';

class AppDirsImpl extends AppDirs {
  static Future<String?> documentsPath() async => null;
}

abstract class AppDirs {
  static Future<String?> documentsPath() => AppDirsImpl.documentsPath();
}
