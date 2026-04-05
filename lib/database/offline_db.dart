import 'package:flutter/foundation.dart' show kIsWeb;

import 'app_database.dart';

/// Single [AppDatabase] for the process (SQLite is not used on web).
class OfflineDb {
  OfflineDb._();

  static AppDatabase? _instance;

  static bool get isSupported => !kIsWeb;

  static AppDatabase get instance {
    if (kIsWeb) {
      throw UnsupportedError('Offline SQLite is not used on web builds.');
    }
    return _instance ??= AppDatabase();
  }
}
