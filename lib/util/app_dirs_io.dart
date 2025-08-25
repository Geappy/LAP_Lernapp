// lib/util/app_dirs_io.dart
import 'package:path_provider/path_provider.dart';
import 'app_dirs_stub.dart';

class AppDirsImpl extends AppDirs {
  static Future<String?> documentsPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
}

abstract class AppDirs {
  static Future<String?> documentsPath() => AppDirsImpl.documentsPath();
}
