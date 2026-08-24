import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';

class StudentPortalsPage extends StatelessWidget {
  const StudentPortalsPage({super.key});

  static final Uri sapPortal = Uri.parse('https://kiitportal.kiituniversity.net/');
  static final Uri kayaPortal = Uri.parse('https://kaya.cse.kiit.ac.in/login/');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KiitSpacing.x4),
          children: [
            Text(
              'KIIT Portals',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: KiitSpacing.x2),
            Text(
              'Quick access to academic systems used alongside attendance.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: KiitSpacing.x5),
            _PortalTile(
              title: 'KIIT SAP Portal',
              subtitle: 'Academic profile, exam, fee, and university records',
              url: sapPortal,
              child: const KiitLogo(height: 42),
            ),
            const SizedBox(height: KiitSpacing.x3),
            _PortalTile(
              title: 'KIIT KAYA',
              subtitle: 'Course resources and classroom learning tools',
              url: kayaPortal,
              child: Image.asset(
                'assets/branding/kaya_icon.png',
                height: 42,
                width: 42,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.school_outlined,
                  color: KiitColors.brandPrimaryStrong,
                  size: 36,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalTile extends StatelessWidget {
  const _PortalTile({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Uri url;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KiitCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox(
          width: 54,
          height: 54,
          child: Center(child: child),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.open_in_new),
        onTap: () async {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        },
      ),
    );
  }
}
