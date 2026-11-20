import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_shell_web.dart' if (dart.library.io) 'app_shell_io.dart';
import 'core/sync/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeBackgroundAttendanceSync();
  } catch (_) {
    // Foreground synchronization remains available if OS scheduling is disabled.
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF111915),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const AttendanceApp());
}
