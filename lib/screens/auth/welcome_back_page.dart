import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:ecommerce_int2/models/login_request.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/utils/validation_utils.dart';
import 'package:ecommerce_int2/screens/main/main_page.dart';
import 'package:ecommerce_int2/widgets/modern_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'register_page.dart';

class WelcomeBackPage extends StatefulWidget {
  final String? initialUsername;

  const WelcomeBackPage({super.key, this.initialUsername});

  @override
  _WelcomeBackPageState createState() => _WelcomeBackPageState();
}

class _WelcomeBackPageState extends State<WelcomeBackPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController emailController;
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true; // Default to true for persistent login

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController(text: widget.initialUsername ?? '');
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final loginRequest = LoginRequest(
      email: emailController.text.trim(),
      password: passwordController.text,
      rememberMe: _rememberMe,
    );

    final response = await authProvider.login(loginRequest);

    if (response.success) {
      // Navigate to main page
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainPage()),
        (route) => false,
      );
    } else {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget welcomeBack = Text(
      'PlanetMM မှကြိုဆိုပါတယ်။',
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        shadows: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.25),
            offset: Offset(0, 6),
            blurRadius: 16.0,
          )
        ],
      ),
    );

    Widget subTitle = Padding(
        padding: const EdgeInsets.only(right: 56.0),
        child: Text(
          'သင့်အကောင့်ထဲသို့ ဝင်ပါ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                height: 1.4,
              ),
        ));

    Widget loginButton = Positioned(
      left: MediaQuery.of(context).size.width / 4,
      bottom: 12, // Adjusted to add more space above button
      child: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return InkWell(
            onTap: authProvider.isLoading ? null : _handleLogin,
            child: Container(
              width: MediaQuery.of(context).size.width / 2,
              height: 60, // Reduced from 80 to make Remember Me visible
              decoration: BoxDecoration(
                // PlanetMM primary gradient for login button
                gradient: AppTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brightPurple.withValues(alpha: 0.4),
                    offset: const Offset(0, 8),
                    blurRadius: 20.0,
                    spreadRadius: -4,
                  )
                ],
                borderRadius: BorderRadius.circular(9.0),
              ),
              child: Center(
                child: authProvider.isLoading
                    ? ModernLoadingIndicator(
                        size: 24,
                        color: Colors.white,
                      )
                    : Text(
                        "ဝင်ရောက်မည်",
                        style: const TextStyle(
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
      ),
    );

    Widget loginForm = SizedBox(
      height: 280, // Increased height to accommodate content without overflow
      child: Stack(
        children: <Widget>[
          // Form container with scrollable content to prevent overflow
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              width: MediaQuery.of(context).size.width,
              constraints: const BoxConstraints(
                minHeight: 190, // Increased to accommodate all content
                maxHeight: 220, // Increased to prevent overflow
              ),
              padding: const EdgeInsets.only(
                left: 32.0,
                right: 12.0,
                top: 8.0,
                bottom: 24.0, // Space above button
              ),
              decoration: BoxDecoration(
                color: Color.fromRGBO(255, 255, 255, 0.8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  // Make form scrollable to prevent overflow
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Username field with optimized padding
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextFormField(
                          controller: emailController,
                          style: const TextStyle(fontSize: 16.0),
                          decoration: InputDecoration(
                            hintText: 'အသုံးပြုသူအမည်',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10.0,
                              horizontal: 0,
                            ),
                            isDense: true,
                          ),
                          validator: ValidationUtils.validateUsername,
                        ),
                      ),
                      // Password field with optimized padding
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextFormField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(fontSize: 16.0),
                          decoration: InputDecoration(
                            hintText: 'လျို့ဝှက်နံပါတ်',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10.0,
                              horizontal: 0,
                            ),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.grey,
                                size: 20,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: ValidationUtils.validatePassword,
                        ),
                      ),
                      // Remember me checkbox with optimized padding
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() {
                                  _rememberMe = value ?? false;
                                });
                              },
                              activeColor: AppTheme.brightPurple,
                              checkColor: Colors.white,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            Flexible(
                              child: Text(
                                'အကောင့်ကို မှတ်ထားမယ်',
                                style: const TextStyle(fontSize: 14.0),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Login button positioned at bottom
          loginButton,
        ],
      ),
    );

    Widget forgotPassword = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: <Widget>[
            Text(
              'လျို့ဝှက်နံပါတ်မေ့သွားသလား ',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Color.fromRGBO(255, 255, 255, 0.5),
                fontSize: 14.0,
              ),
            ),
            InkWell(
              onTap: () {
                // TODO: Implement forgot password
              },
              child: Text(
                'လျို့ဝှက်နံပါတ် အသစ်ပြန်သတ်မှတ်မယ်',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Sign Up as a primary button matching Login button style
    Widget signUpLink = Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "အကောင့်မရှိသေးဘူးလား။",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Color.fromRGBO(255, 255, 255, 0.7),
              fontSize: 14.0,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RegisterPage()),
                );
              },
              child: Container(
                width: MediaQuery.of(context).size.width / 2,
                height: 60, // Match Login button height for consistency
                decoration: BoxDecoration(
                  // PlanetMM primary gradient matching Login button
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brightPurple.withValues(alpha: 0.4),
                      offset: const Offset(0, 8),
                      blurRadius: 20.0,
                      spreadRadius: -4,
                    )
                  ],
                  borderRadius: BorderRadius.circular(9.0),
                ),
                child: Center(
                  child: Text(
                    "အကောင့်ဖွင့်မည်",
                    style: const TextStyle(
                      color: Color(0xfffefefe),
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.normal,
                      fontSize: 20.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          if (!mounted) return;
          setState(() {});
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height,
              child: Stack(
                children: <Widget>[
                  // New PlanetMM in-app artwork as full-screen background
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                    ),
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.85,
                      child: Image.asset(
                        'assets/icons/planetmm_inapplogo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  // Soft overlay to keep text readable
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
                  Padding(
                    padding: const EdgeInsets.only(left: 28.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Spacer(flex: 3),
                        welcomeBack,
                        Spacer(),
                        subTitle,
                        Spacer(flex: 2),
                        loginForm,
                        Spacer(flex: 2),
                        forgotPassword,
                        signUpLink
                      ],
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
