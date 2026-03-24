import 'package:ecommerce_int2/widgets/dynamic_content_page.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:flutter/material.dart';

class LicensePage extends StatelessWidget {
  const LicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicContentPage(
      pageSlug: 'license',
      pageTitle: 'License',
      icon: Icons.copyright_outlined,
      headerColor: Colors.orange,
    );
  }
}

