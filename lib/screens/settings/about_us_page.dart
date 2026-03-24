import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/page_content.dart';
import 'package:ecommerce_int2/services/page_content_service.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:ecommerce_int2/utils/logger.dart' as app_logger;
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// About Us page with original design
/// Content is now managed from Dashboard via dedicated About Us Management
class AboutUsPage extends StatefulWidget {
  const AboutUsPage({super.key});

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage> {
  AboutUsContent? _aboutUsContent;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final content = await PageContentService.getAboutUsContent();

      if (mounted) {
        setState(() {
          _aboutUsContent = content;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      app_logger.Logger.error(
        'AboutUsPage - Error loading content: $e',
        tag: 'AboutUsPage',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Strip HTML tags from text for clean display
  String _stripHtmlTags(String html) {
    if (html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    // Use content from API or defaults
    final companyName = _aboutUsContent?.companyName ?? 'PLANETmm';
    final tagline = _aboutUsContent?.tagline ?? 'Pansy & Lincoln';
    final subtitle = _aboutUsContent?.subtitle ?? 'All-in-One Network Myanmar';
    final logoUrl = _aboutUsContent?.logoUrl ?? '';
    final aboutBody1 = _aboutUsContent?.aboutBody1 ??
        'PLANETmm is Myanmar\'s premier all-in-one digital network platform, bringing together lifestyle, commerce, rewards, and community into a single seamless experience for users across the country.';
    final aboutBody2 = _aboutUsContent?.aboutBody2 ??
        'Our platform is built to connect people, businesses, and services in a modern, convenient, and secure way. We focus on delivering real value through exclusive promotions, smart loyalty points, easy payments, and a smooth shopping journey. With a strong technical foundation and a customer-first mindset, we are continuously improving to match the needs of Myanmar users in the digital age.';
    final mission = _aboutUsContent?.mission ??
        'To empower Myanmar\'s digital economy by connecting people, businesses, and communities through innovative technology, reliable services, and a rewarding experience that adds real value to everyday life.';
    final vision = _aboutUsContent?.vision ??
        'To become Myanmar\'s leading all-in-one digital platform, transforming how people shop, earn rewards, communicate, and live — by combining technology, creativity, and local understanding into a single powerful ecosystem.';
    final email = _aboutUsContent?.email ?? 'support@planetmm.com';
    final phone = _aboutUsContent?.phone ?? '+95 9 123 456 789';
    final address = _aboutUsContent?.address ?? 'No. 123, Example Street, Yangon, Myanmar';
    final version = _aboutUsContent?.version ?? '1.0.2';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: darkGrey),
        title: const Text(
          'About Us',
          style: TextStyle(
            color: darkGrey,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: AppPullToRefresh(
        onRefresh: _loadContent,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Card (static branding)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.deepBlue,
                            AppTheme.brightPurple,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.brightPurple.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.2),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: logoUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(40),
                                    child: Image.network(
                                      logoUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Image.asset(
                                          'assets/icons/planetmm_logo.png',
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Icon(
                                              Icons.business,
                                              color: Colors.white,
                                              size: 40,
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  )
                                : ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: Image.asset(
                                'assets/icons/planetmm_logo.png',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.business,
                                    color: Colors.white,
                                    size: 40,
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            companyName,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                          if (tagline.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                              tagline,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          ],
                          if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                              subtitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // About Section
                    _buildSection(
                      title: 'About Us',
                      icon: Icons.info_outline,
                      children: [
                        Text(
                          _stripHtmlTags(aboutBody1),
                          style: const TextStyle(
                            fontSize: 15,
                            color: darkGrey,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _stripHtmlTags(aboutBody2),
                          style: const TextStyle(
                            fontSize: 15,
                            color: darkGrey,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Mission Section
                    _buildSection(
                      title: 'Our Mission',
                      icon: Icons.flag_outlined,
                      children: [
                        Text(
                          _stripHtmlTags(mission),
                          style: const TextStyle(
                            fontSize: 15,
                            color: darkGrey,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Vision Section
                    _buildSection(
                      title: 'Our Vision',
                      icon: Icons.visibility_outlined,
                      children: [
                        Text(
                          _stripHtmlTags(vision),
                          style: const TextStyle(
                            fontSize: 15,
                            color: darkGrey,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Contact Section
                    _buildSection(
                      title: 'Contact Us',
                      icon: Icons.contact_mail_outlined,
                      children: [
                        _buildContactItem(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: email,
                        ),
                        const SizedBox(height: 12),
                        _buildContactItem(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          value: phone,
                        ),
                        const SizedBox(height: 12),
                        _buildContactItem(
                          icon: Icons.location_on_outlined,
                          label: 'Address',
                          value: address,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Version Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.grey[600], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Version $version',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: mediumYellow.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: mediumYellow,
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: darkGrey,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildContactItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: mediumYellow, size: 20),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: darkGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

