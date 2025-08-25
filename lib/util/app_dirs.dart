// lib/util/app_dirs.dart
import 'app_dirs_stub.dart'
  if (dart.library.io) 'app_dirs_io.dart'
  if (dart.library.html) 'app_dirs_web.dart';

export 'app_dirs_stub.dart';
