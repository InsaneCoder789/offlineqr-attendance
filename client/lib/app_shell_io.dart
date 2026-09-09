import 'dart:async';

import 'package:flutter/material.dart';

import 'core/database/local_database.dart';
import 'core/network/api_config.dart';
import 'core/security/secure_device_key_store.dart';
import 'core/security/student_auth_store.dart';
import 'core/sync/attendance_proof_sync_service.dart';
import 'core/sync/bootstrap_sync_service.dart';
import 'features/student_auth/student_login_page.dart';
import 'features/student_shell/student_home.dart';
import 'ui/kiit_components.dart';
import 'ui/kiit_theme.dart';

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  late final Future<LocalAttendanceDatabase> _databaseFuture;
  late final StudentAuthStore _authStore;
  LocalAttendanceDatabase? _database;

  @override
  void initState() {
    super.initState();
    _authStore = StudentAuthStore();
    _databaseFuture = LocalAttendanceDatabase.openDefault().then((database) {
      _database = database;
      return database;
    });
  }

  @override
  void dispose() {
    _database?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KIIT Attendance',
      debugShowCheckedModeBanner: false,
      theme: buildKiitTheme(),
      onUnknownRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => const KiitNotFoundPage(),
      ),
      home: FutureBuilder<LocalAttendanceDatabase>(
        future: _databaseFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(KiitSpacing.x5),
                    child: KiitNoticeBanner(
                      title: 'Attendance storage unavailable',
                      message:
                          'The app could not open its protected local records. Restart the app before attempting attendance.',
                      tone: StatusTone.error,
                    ),
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const _AppLaunchScreen();
          }
          return StudentAppShell(
            database: snapshot.data!,
            keyStore: SecureStorageDeviceKeyStore(),
            authStore: _authStore,
          );
        },
      ),
    );
  }
}

class StudentAppShell extends StatefulWidget {
  const StudentAppShell({
    super.key,
    required this.database,
    required this.keyStore,
    required this.authStore,
  });

  final LocalAttendanceDatabase database;
  final SecureStorageDeviceKeyStore keyStore;
  final StudentAuthStore authStore;

  @override
  State<StudentAppShell> createState() => _StudentAppShellState();
}

class _StudentAppShellState extends State<StudentAppShell>
    with WidgetsBindingObserver {
  int refreshToken = 0;
  bool syncing = false;
  String? syncError;
  late bool loggedIn;
  bool checkingSession = true;
  Timer? syncPoller;
  Duration _pollInterval = const Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    loggedIn = false;
    WidgetsBinding.instance.addObserver(this);
    _restoreAuthenticatedSession();
  }

  Future<void> _restoreAuthenticatedSession() async {
    final session = await widget.authStore.read();
    if (!mounted) return;
    setState(() {
      loggedIn = session != null &&
          widget.database.getCurrentStudent()?.id == session.studentId;
      checkingSession = false;
    });
    if (loggedIn) {
      await sync();
      _startSyncPolling();
    }
  }

  @override
  void dispose() {
    syncPoller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !syncing) {
      sync();
      _startSyncPolling();
    }
    if (state == AppLifecycleState.paused) {
      syncPoller?.cancel();
      syncPoller = null;
    }
  }

  Future<void> sync() async {
    await _syncInternal(forceProofSync: true);
  }

  Future<bool> _syncInternal({
    bool refreshViews = true,
    bool forceProofSync = false,
  }) async {
    if (syncing || !mounted) return false;
    setState(() => syncing = true);
    try {
      final baseUri = apiBaseUri();
      final proofSync = await AttendanceProofSyncService(
        database: widget.database,
        baseUri: baseUri,
        keyStore: widget.keyStore,
      ).syncPendingProofs(force: forceProofSync);
      var bootstrapOk = true;
      try {
        await BootstrapSyncService(
          database: widget.database,
          baseUri: baseUri,
          authStore: widget.authStore,
        ).sync();
      } catch (_) {
        bootstrapOk = false;
      }
      if (!mounted) return false;
      if (proofSync.rejected > 0) {
        setState(() {
          if (refreshViews) {
            refreshToken++;
          }
          syncError = 'Review needed';
        });
        return false;
      }
      setState(() {
        if (refreshViews) {
          refreshToken++;
        }
        syncError =
            !bootstrapOk || proofSync.retryPending > 0 ? 'Sync pending' : null;
      });
      _pollInterval = proofSync.retryPending > 0
          ? const Duration(seconds: 5)
          : const Duration(seconds: 30);
      return bootstrapOk && proofSync.retryPending == 0;
    } catch (_) {
      if (mounted) {
        setState(() => syncError = 'Sync failed');
      }
      _pollInterval = const Duration(seconds: 10);
      return false;
    } finally {
      if (mounted) {
        setState(() => syncing = false);
      }
    }
  }

  void _startSyncPolling() {
    if (syncPoller != null || !loggedIn) return;
    // Foreground polling makes captured proofs the first work attempted as
    // soon as the backend becomes reachable again. The outbox backoff still
    // protects the server during a real outage.
    void scheduleNext() {
      syncPoller = Timer(_pollInterval, () async {
        if (!mounted || syncing || !loggedIn) return;
        await _syncInternal(forceProofSync: true);
        if (mounted && loggedIn) scheduleNext();
      });
    }

    scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    if (checkingSession) {
      return const _AppLaunchScreen();
    }
    if (!loggedIn) {
      return StudentLoginPage(
        database: widget.database,
        onLoginComplete: () {
          setState(() {
            loggedIn = true;
            refreshToken++;
            syncError = null;
          });
          _startSyncPolling();
        },
        authStore: widget.authStore,
      );
    }
    return StudentHome(
      database: widget.database,
      keyStore: widget.keyStore,
      refreshToken: refreshToken,
      onSync: sync,
      onAttendanceRecorded: () => _syncInternal(forceProofSync: true),
      syncing: syncing,
      syncError: syncError,
    );
  }
}

class _AppLaunchScreen extends StatelessWidget {
  const _AppLaunchScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KiitColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 104,
                height: 104,
                padding: const EdgeInsets.all(KiitSpacing.x4),
                decoration: BoxDecoration(
                  color: KiitColors.brandPrimarySubtle,
                  borderRadius: BorderRadius.circular(KiitRadius.hero),
                  border: Border.all(color: KiitColors.border),
                ),
                child: Image.asset(
                  'assets/branding/app_icon/kiit_splash_mark_1024.png',
                ),
              ),
              const SizedBox(height: KiitSpacing.x5),
              Text(
                'KIIT Attendance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: KiitSpacing.x4),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
