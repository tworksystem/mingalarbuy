import 'package:ecommerce_int2/widgets/dynamic_content_page.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:flutter/material.dart';

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicContentPage(
      pageSlug: 'terms-of-use',
      pageTitle: 'Terms of Use',
      icon: Icons.description_outlined,
      headerColor: AppTheme.deepBlue,
    );
  }
}

