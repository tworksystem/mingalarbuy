import 'package:ecommerce_int2/widgets/dynamic_content_page.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ReturnPolicyPage extends StatelessWidget {
  const ReturnPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicContentPage(
      pageSlug: 'return-policy',
      pageTitle: 'Return Policy',
      icon: Icons.assignment_return_outlined,
      headerColor: Colors.teal,
    );
  }
}

