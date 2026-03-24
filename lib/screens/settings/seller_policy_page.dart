import 'package:ecommerce_int2/widgets/dynamic_content_page.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SellerPolicyPage extends StatelessWidget {
  const SellerPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicContentPage(
      pageSlug: 'seller-policy',
      pageTitle: 'Seller Policy',
      icon: Icons.store_outlined,
      headerColor: Colors.green,
    );
  }
}

