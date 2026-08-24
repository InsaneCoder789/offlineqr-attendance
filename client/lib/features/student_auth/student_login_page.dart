import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/database/local_database.dart';
import '../../core/network/api_config.dart';
import '../../core/sync/bootstrap_models.dart';
import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';

class StudentLoginPage extends StatefulWidget {
  const StudentLoginPage({
    super.key,
    required this.database,
    required this.onLoginComplete,
  });

  final LocalAttendanceDatabase database;
  final VoidCallback onLoginComplete;

  @override
  State<StudentLoginPage> createState() => _StudentLoginPageState();
}

class _StudentLoginPageState extends State<StudentLoginPage> {
  final emailController = TextEditingController(text: '24155866@kiit.ac.in');
  bool loading = false;
  String? error;

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailController.text.trim().toLowerCase();
    final roll = rollFromEmail(email);
    if (roll == null) {
      setState(() => error = 'Use your KIIT email, for example 24155866@kiit.ac.in.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await http
          .post(
            apiBaseUri().resolve('/api/v1/auth/dev-login'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(apiRequestTimeout);
      if (response.statusCode != 200) {
        throw StateError(_messageFrom(response.body));
      }
      final payload = BootstrapSyncPayload.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (payload.student.rollNumber != roll) {
        throw StateError('The KIIT email did not match the returned student record.');
      }
      widget.database.applyBootstrap(payload);
      widget.onLoginComplete();
    } catch (exception) {
      if (mounted) {
        setState(() => error = exception.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KiitSpacing.x5),
          children: [
            const SizedBox(height: KiitSpacing.x8),
            const KiitLogo(height: 58),
            const SizedBox(height: KiitSpacing.x8),
            Text(
              'KIIT Attendance',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: KiitSpacing.x2),
            Text(
              'Sign in with your KIIT email. Your roll number maps to your official section, courses, timetable, and attendance records.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: KiitSpacing.x8),
            KiitCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Student Login', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: KiitSpacing.x4),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => loading ? null : login(),
                    decoration: const InputDecoration(
                      labelText: 'KIIT email',
                      hintText: '24155866@kiit.ac.in',
                      prefixIcon: Icon(Icons.alternate_email),
                      border: OutlineInputBorder(),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(loading ? 'Signing in' : 'Continue'),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: KiitSpacing.x4),
                    StatusChip(
                      label: error!,
                      icon: Icons.error_outline,
                      tone: StatusTone.error,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: KiitSpacing.x5),
            const StatusChip(
              label: 'Demo identity: 24155866@kiit.ac.in',
              icon: Icons.verified_user_outlined,
              tone: StatusTone.info,
            ),
          ],
        ),
      ),
    );
  }

  String _messageFrom(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      return error?['message'] as String? ?? body;
    } catch (_) {
      return body;
    }
  }
}

String? rollFromEmail(String email) {
  final match = RegExp(r'^([0-9]{5,12})@kiit\.ac\.in$').firstMatch(email);
  return match?.group(1);
}
