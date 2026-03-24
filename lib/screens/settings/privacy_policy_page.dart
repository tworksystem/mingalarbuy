import 'package:ecommerce_int2/widgets/dynamic_content_page.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicContentPage(
      pageSlug: 'privacy-policy',
      pageTitle: 'Privacy Policy',
      icon: Icons.privacy_tip_outlined,
      headerColor: AppTheme.brightPurple,
    );
  }
}

