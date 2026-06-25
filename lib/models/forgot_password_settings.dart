class CustomerServiceConfig {
  final bool enabled;
  final String label;
  final String link;

  const CustomerServiceConfig({
    required this.enabled,
    required this.label,
    required this.link,
  });

  bool get isVisible => enabled && label.trim().isNotEmpty && link.trim().isNotEmpty;

  factory CustomerServiceConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CustomerServiceConfig(
        enabled: false,
        label: '',
        link: '',
      );
    }
    return CustomerServiceConfig(
      enabled: json['enabled'] == true,
      label: (json['label'] as String?)?.trim() ?? '',
      link: (json['link'] as String?)?.trim() ?? '',
    );
  }
}

class ForgotPasswordSettings {
  final String emailDomain;
  final String hintText;
  final CustomerServiceConfig customerService;

  const ForgotPasswordSettings({
    required this.emailDomain,
    required this.hintText,
    required this.customerService,
  });

  String get exampleEmail => 'myname@$emailDomain';

  factory ForgotPasswordSettings.fromJson(Map<String, dynamic> json) {
    return ForgotPasswordSettings(
      emailDomain: (json['email_domain'] as String?)?.trim() ?? '',
      hintText: (json['hint_text'] as String?)?.trim() ?? '',
      customerService: CustomerServiceConfig.fromJson(
        json['customer_service'] as Map<String, dynamic>?,
      ),
    );
  }
}
