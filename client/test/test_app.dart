import 'package:flutter/material.dart';

import 'package:client/core/database/local_database.dart';
import 'package:client/core/security/device_crypto.dart';
import 'package:client/features/student_shell/student_home.dart';

class TestApp extends StatelessWidget {
  const TestApp({super.key, required this.database, this.keyStore});

  final LocalAttendanceDatabase database;
  final DeviceKeyStore? keyStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: StudentHome(
        database: database,
        keyStore: keyStore ?? InMemoryDeviceKeyStore(),
      ),
    );
  }
}
