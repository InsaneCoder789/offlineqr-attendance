import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/kiit_components.dart';
import '../../ui/kiit_theme.dart';

class StudentPortalsPage extends StatelessWidget {
  const StudentPortalsPage({super.key});

  static final Uri sapPortal =
      Uri.parse('https://kiitportal.kiituniversity.net/');
  static final Uri kayaPortal = Uri.parse('https://kaya.cse.kiit.ac.in/login/');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KiitSpacing.x4,
            KiitSpacing.x5,
            KiitSpacing.x4,
            KiitSpacing.x8,
          ),
          children: [
            const KiitPageHeader(
              title: 'KIIT services',
              description:
                  'Open the university services connected to your academic life.',
            ),
            const SizedBox(height: KiitSpacing.x5),
            _PortalTile(
              title: 'KIIT SAP Portal',
              subtitle: 'Academic profile, examinations, fees and records',
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
    return Material(
      color: KiitColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KiitRadius.large),
        side: const BorderSide(color: KiitColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final opened = await launchUrl(
            url,
            mode: LaunchMode.externalApplication,
          );
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$title could not be opened.')),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(KiitSpacing.x4),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                padding: const EdgeInsets.all(KiitSpacing.x2),
                decoration: BoxDecoration(
                  color: KiitColors.brandPrimarySubtle,
                  borderRadius: BorderRadius.circular(KiitRadius.medium),
                ),
                child: Center(child: child),
              ),
              const SizedBox(width: KiitSpacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: KiitSpacing.x1),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: KiitSpacing.x2),
              const Icon(
                Icons.open_in_new_rounded,
                color: KiitColors.brandPrimaryStrong,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
