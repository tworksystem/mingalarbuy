import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/forgot_password_settings.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/services/forgot_password_settings_service.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:ecommerce_int2/utils/html_link_launcher.dart';
import 'package:ecommerce_int2/utils/validation_utils.dart';
import 'package:ecommerce_int2/widgets/modern_loading_indicator.dart';
import 'package:ecommerce_int2/widgets/planetmm_auth_background.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();

  ForgotPasswordSettings? _settings;
  bool _loadingSettings = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings({bool forceRefresh = false}) async {
    setState(() {
      _loadingSettings = true;
    });

    final settings = await ForgotPasswordSettingsService.getSettings(
      forceRefresh: forceRefresh,
    );

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loadingSettings = false;
    });
  }

  String _resolveAccountLogin(String input, String emailDomain) {
    final value = input.trim();
    if (value.contains('@')) {
      return value.toLowerCase();
    }
    return '${value.toLowerCase()}@$emailDomain';
  }

  String? _validateAccountInput(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'အီးမေးလ် ထည့်ရန် လိုအပ်ပါတယ်';
    }

    final trimmed = value.trim();
    if (trimmed.contains('@')) {
      final emailError = ValidationUtils.validateEmail(trimmed);
      if (emailError != null) {
        return 'မှန်ကန်သော အီးမေးလ် ထည့်ပါ';
      }
      return null;
    }

    if (trimmed.length < 3) {
      return 'အသုံးပြုသူအမည် အနည်းဆုံး အက္ခရာ ၃ လုံးဖြစ်ရမယ်';
    }

    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(trimmed)) {
      return 'အက္ခရာ၊ နံပါတ်၊ . _ - သာ သုံးနိုင်ပါတယ်';
    }

    return null;
  }

  bool _isNetworkFailureMessage(String message) {
    final lower = message.toLowerCase();
    return lower.contains('network') ||
        lower.contains('unreachable') ||
        lower.contains('connection') ||
        lower.contains('internet') ||
        lower.contains('timeout');
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting || _settings == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loginValue = _resolveAccountLogin(
      _emailController.text,
      _settings!.emailDomain,
    );

    final response = await authProvider.forgotPassword(loginValue);

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
    });

    const genericMessage =
        'အကောင့် ရှိပါက reset link ပို့ပြီးပါပြီ။ Inbox နှင့် spam folder စစ်ဆေးပါ။';

    final String message;
    if (!response.success && _isNetworkFailureMessage(response.message)) {
      message = response.message.isNotEmpty
          ? response.message
          : 'အင်တာနက် စစ်ဆေးပြီး ထပ်စမ်းကြည့်ပါ။';
    } else {
      // Avoid account enumeration — same message for success and unknown email.
      message = genericMessage;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    String? labelText,
  }) {
    final borderRadius = BorderRadius.circular(8);
    final enabledBorderSide = BorderSide(color: Colors.grey.shade300);

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: enabledBorderSide,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: enabledBorderSide,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: AppTheme.brightPurple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final topPadding = MediaQuery.of(context).padding.top + 8;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const PlanetMMAuthBackground(child: SizedBox.expand()),
            RefreshIndicator(
              onRefresh: () => _loadSettings(forceRefresh: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(24, topPadding, 24, 40),
                children: [
                  IconButton(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'လျို့ဝှက်နံပါတ် ပြန်သတ်မှတ်မယ်',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      shadows: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.15),
                          offset: Offset(0, 5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'မှတ်ပုံတင်ထားသော အီးမေးလ်ကို ထည့်ပြီး reset link ရယူပါ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_loadingSettings)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: ModernLoadingIndicator(
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else if (settings != null) ...[
                    _HintCard(settings: settings),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(255, 255, 255, 0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Form(
                        key: _formKey,
                        child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_isSubmitting) _handleSubmit();
                          },
                          style: const TextStyle(fontSize: 16),
                          decoration: _inputDecoration(
                            hintText: settings.exampleEmail,
                            labelText: 'အီးမေးလ်',
                          ),
                          validator: _validateAccountInput,
                          enabled: !_isSubmitting,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Semantics(
                        button: true,
                        label: 'Reset Email ပို့မယ်',
                        child: InkWell(
                          onTap: _isSubmitting ? null : _handleSubmit,
                          child: Container(
                            width: MediaQuery.of(context).size.width * 0.65,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: mainButton,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: shadow,
                            ),
                            child: Center(
                              child: _isSubmitting
                                  ? const ModernLoadingIndicator(
                                      size: 24,
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      'Reset Email ပို့မယ်',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 18,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (settings.customerService.isVisible) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () => HtmlLinkLauncher.launch(
                                    context,
                                    settings.customerService.link,
                                  ),
                          icon: const Icon(Icons.support_agent, size: 20),
                          label: Text(settings.customerService.label),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final ForgotPasswordSettings settings;

  const _HintCard({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.hintText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                if (!settings.hintText.contains(settings.exampleEmail)) ...[
                  const SizedBox(height: 6),
                  Text(
                    'ဥပမာ — ${settings.exampleEmail}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
