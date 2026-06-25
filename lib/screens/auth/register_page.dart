import 'package:ecommerce_int2/models/register_request.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/utils/validation_utils.dart';
import 'package:ecommerce_int2/widgets/modern_loading_indicator.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'welcome_back_page.dart';

/// Professional Register Page with clean architecture
///
/// Features:
/// - Simplified, maintainable layout structure
/// - Proper keyboard handling
/// - Responsive design
/// - Error handling
/// - Material Design best practices
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  RegisterPageState createState() => RegisterPageState();
}

class RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    phoneController.dispose();
    usernameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    // Validate form
    if (!_formKey.currentState!.validate()) {
      // Scroll to first error field
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final registerRequest = RegisterRequest(
      username: usernameController.text.trim(),
      password: passwordController.text,
      phone: phoneController.text.trim().isNotEmpty
          ? phoneController.text.trim()
          : null,
    );

    final response = await authProvider.register(registerRequest);

    // Check if widget is still mounted before using context
    if (!mounted) return;

    if (response.success) {
      // Navigate to login page with username pre-filled
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => WelcomeBackPage(
            initialUsername: usernameController.text.trim(),
          ),
        ),
        (route) => false,
      );
    } else {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          if (mounted) {
            setState(() {});
          }
        },
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height,
              child: Stack(
                children: <Widget>[
                  // Background with gradient fallback
                  _buildBackground(),

                  // Main content
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Spacer(flex: 1),

                        // Back button
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          color: Colors.white,
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),

                        const SizedBox(height: 8.0),

                        // Title
                        _buildTitle(),

                        const SizedBox(height: 8.0),

                        // Subtitle
                        _buildSubtitle(),

                        Spacer(flex: 1),

                        // Registration form
                        _buildRegisterForm(),

                        Spacer(flex: 1),

                        // Login link
                        _buildLoginLink(),

                        const SizedBox(height: 20.0),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build background with image and gradient overlay
  Widget _buildBackground() {
    return Stack(
      children: [
        // Base black container
        Container(
          decoration: const BoxDecoration(
            color: Colors.black,
          ),
        ),

        // Background image
        Positioned.fill(
          child: Opacity(
            opacity: 0.85,
            child: Image.asset(
              'assets/icons/planetmm_inapplogo.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback to gradient if image fails
                return Container(
                  decoration: const BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                  ),
                );
              },
            ),
          ),
        ),

        // Gradient overlay for text readability
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.75),
                Colors.black.withOpacity(0.55),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  /// Build title widget
  Widget _buildTitle() {
    return Text(
      'PlanetMM',
      style: TextStyle(
        color: Colors.white,
        fontSize: 34.0,
        fontWeight: FontWeight.bold,
        shadows: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.15),
            offset: Offset(0, 5),
            blurRadius: 10.0,
          )
        ],
      ),
    );
  }

  /// Build subtitle widget
  Widget _buildSubtitle() {
    return Padding(
      padding: const EdgeInsets.only(right: 56.0),
      child: Text(
        'Pansy & Lincoln All-in-one Network Myanmar',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16.0,
        ),
      ),
    );
  }

  /// Build registration form
  Widget _buildRegisterForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 20.0,
            vertical: 12.0,
          ),
          decoration: BoxDecoration(
            color: Color.fromRGBO(255, 255, 255, 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildTextField(
                    controller: usernameController,
                    hintText: 'အသုံးပြုသူအမည်* (planetmm)',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'အသုံးပြုသူအမည် ထည့်ရန် လိုအပ်ပါတယ်';
                      }
                      if (value.trim().length < 3) {
                        return 'အသုံးပြုသူအမည် အနည်းဆုံး အက္ခရာ ၃ လုံးဖြစ်ရမယ်';
                      }
                      return null;
                    },
                  ),
                  _buildTextField(
                    controller: phoneController,
                    hintText: 'ဖုန်းနံပါတ် * (မဖြစ်မနေ လိုအပ်ပါသည်)',
                    keyboardType: TextInputType.phone,
                    validator: ValidationUtils.validatePhone,
                  ),
                  _buildPasswordField(
                    controller: passwordController,
                    hintText: 'လျို့ဝှက်နံပါတ် *',
                    obscureText: _obscurePassword,
                    onToggleVisibility: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    validator: ValidationUtils.validatePassword,
                  ),
                  _buildPasswordField(
                    controller: confirmPasswordController,
                    hintText: 'လျို့ဝှက်နံပါတ် အတည်ပြုချက် *',
                    obscureText: _obscureConfirmPassword,
                    onToggleVisibility: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                    validator: (value) =>
                        ValidationUtils.validateConfirmPassword(
                      value,
                      passwordController.text,
                    ),
                  ),
                  const SizedBox(height: 12.0),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(child: _buildRegisterButton()),
      ],
    );
  }

  /// Shared rounded input decoration for auth fields
  InputDecoration _authInputDecoration({required String hintText}) {
    final borderRadius = BorderRadius.circular(8);
    final enabledBorderSide = BorderSide(color: Colors.grey.shade300);

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: Colors.grey[600],
        fontSize: 16.0,
      ),
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

  /// Build text field widget
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16.0,
          color: Colors.black87,
        ),
        decoration: _authInputDecoration(hintText: hintText),
        validator: validator,
      ),
    );
  }

  /// Build password field widget
  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: TextInputType.visiblePassword,
        enableSuggestions: false,
        autocorrect: false,
        style: const TextStyle(
          fontSize: 16.0,
          color: Colors.black87,
        ),
        decoration: _authInputDecoration(hintText: hintText).copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              obscureText ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey[700],
            ),
            onPressed: onToggleVisibility,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        validator: validator,
      ),
    );
  }

  /// Build register button
  Widget _buildRegisterButton() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return InkWell(
          onTap: authProvider.isLoading ? null : _handleRegister,
          child: Container(
            width: MediaQuery.of(context).size.width / 2,
            height: 60,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.brightPurple.withOpacity(0.4),
                  offset: const Offset(0, 8),
                  blurRadius: 20.0,
                  spreadRadius: -4,
                )
              ],
              borderRadius: BorderRadius.circular(9.0),
            ),
            child: Center(
              child: authProvider.isLoading
                  ? const ModernLoadingIndicator(
                      size: 24,
                      color: Colors.white,
                    )
                  : const Text(
                      "စာရင်းသွင်းမယ်",
                      style: TextStyle(
                        color: Color(0xfffefefe),
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.normal,
                        fontSize: 20.0,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  /// Build login link widget
  Widget _buildLoginLink() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            "အကောင့်ရှိပြီးသားလား ",
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Color.fromRGBO(255, 255, 255, 0.5),
              fontSize: 14.0,
            ),
          ),
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => WelcomeBackPage()),
              );
            },
            child: Text(
              'လော့ဂ်အင်ဝင်မယ်',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
