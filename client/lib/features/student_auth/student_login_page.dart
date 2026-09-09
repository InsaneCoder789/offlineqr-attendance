import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/network/api_config.dart';
import '../../core/security/student_auth_service.dart';
import '../../core/security/student_auth_store.dart';
import '../../core/sync/bootstrap_sync_service.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';

class StudentLoginPage extends StatefulWidget {
  const StudentLoginPage({
    super.key,
    required this.database,
    required this.onLoginComplete,
    required this.authStore,
  });

  final LocalAttendanceDatabase database;
  final VoidCallback onLoginComplete;
  final StudentAuthStore authStore;

  @override
  State<StudentLoginPage> createState() => _StudentLoginPageState();
}

class _StudentLoginPageState extends State<StudentLoginPage> {
  final rollController = TextEditingController();
  final passwordController = TextEditingController();
  bool obscurePassword = true;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    rollController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final roll = rollController.text.trim();
    if (!RegExp(r'^[0-9]{5,12}$').hasMatch(roll) ||
        passwordController.text.isEmpty) {
      setState(() => error = 'Enter your roll number and password.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final auth =
          StudentAuthService(baseUri: apiBaseUri(), store: widget.authStore);
      final result = await auth.login(
        rollNumber: roll,
        password: passwordController.text,
      );
      if (result.mustChangePassword) {
        final changed =
            await _requirePasswordChange(auth, passwordController.text);
        if (!changed) return;
        throw StateError(
            'Password changed. Sign in again with your new password.');
      }
      await BootstrapSyncService(
        database: widget.database,
        baseUri: apiBaseUri(),
        authStore: widget.authStore,
      ).sync();
      widget.onLoginComplete();
    } catch (exception) {
      if (mounted) {
        setState(
            () => error = exception.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<bool> _requirePasswordChange(
      StudentAuthService auth, String currentPassword) async {
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    String? dialogError;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create your password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Your temporary password must be replaced before attendance services can be used.'),
              const SizedBox(height: KiitSpacing.x3),
              TextField(
                controller: newPassword,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: KiitSpacing.x2),
              TextField(
                controller: confirmPassword,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm new password'),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: KiitSpacing.x2),
                Text(dialogError!,
                    style: const TextStyle(color: KiitColors.error)),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                if (newPassword.text != confirmPassword.text) {
                  setDialogState(
                      () => dialogError = 'The passwords do not match.');
                  return;
                }
                try {
                  await auth.changePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword.text,
                  );
                  if (context.mounted) Navigator.of(context).pop(true);
                } catch (error) {
                  setDialogState(() => dialogError =
                      error.toString().replaceFirst('Bad state: ', ''));
                }
              },
              child: const Text('Set password'),
            ),
          ],
        ),
      ),
    );
    newPassword.dispose();
    confirmPassword.dispose();
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth > 600
                  ? (constraints.maxWidth - 480) / 2
                  : KiitSpacing.x5,
              vertical: KiitSpacing.x6,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(KiitSpacing.x3),
                  decoration: BoxDecoration(
                    color: KiitColors.surface,
                    borderRadius: BorderRadius.circular(KiitRadius.large),
                    border: Border.all(color: KiitColors.border),
                  ),
                  child: const KiitLogo(height: 48),
                ),
              ),
              const SizedBox(height: KiitSpacing.x6),
              Text(
                'Welcome to KIIT Attendance',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: KiitSpacing.x3),
              Text(
                'Sign in with your institutional student credentials. Your assigned section and timetable are loaded automatically.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: KiitColors.textSecondary,
                    ),
              ),
              const SizedBox(height: KiitSpacing.x8),
              KiitCard(
                padding: const EdgeInsets.all(KiitSpacing.x5),
                shadow: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Student sign in',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: KiitSpacing.x1),
                    Text(
                      'Use the same roll number registered with KIIT.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: KiitSpacing.x4),
                    TextField(
                      controller: rollController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Roll number',
                        hintText: '24155866',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: KiitSpacing.x4),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => loading ? null : login(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                              () => obscurePassword = !obscurePassword),
                          icon: Icon(obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: KiitSpacing.x4),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: loading ? null : login,
                        icon: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: Text(loading ? 'Signing in' : 'Continue'),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: KiitSpacing.x4),
                      KiitNoticeBanner(
                        title: 'Sign in unsuccessful',
                        message: _friendlyError(error!),
                        tone: StatusTone.error,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: KiitSpacing.x5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: KiitColors.textMuted,
                  ),
                  const SizedBox(width: KiitSpacing.x2),
                  Flexible(
                    child: Text(
                      'Your attendance device remains bound to your student identity.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _friendlyError(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('socket') ||
        normalized.contains('connection') ||
        normalized.contains('network')) {
      return 'The attendance service is currently unreachable. Check your connection and try again.';
    }
    if (normalized.contains('401') || normalized.contains('credential')) {
      return 'The roll number or password is incorrect.';
    }
    return value.replaceAll(RegExp(r'[_]+'), ' ').trim();
  }
}
