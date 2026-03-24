import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:ecommerce_int2/models/register_request.dart';
import 'package:ecommerce_int2/models/login_request.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/utils/validation_utils.dart';
import 'package:ecommerce_int2/screens/main/main_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'welcome_back_page.dart';

class RegisterPageNew extends StatefulWidget {
  const RegisterPageNew({super.key});

  @override
  _RegisterPageNewState createState() => _RegisterPageNewState();
}

class _RegisterPageNewState extends State<RegisterPageNew> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Split full name into first and last name (last name optional)
    final fullName = firstNameController.text.trim();
    String firstName = '';
    String lastName = '';
    if (fullName.isNotEmpty) {
      final parts = fullName.split(RegExp(r'\s+'));
      firstName = parts.first;
      if (parts.length > 1) {
        lastName = parts.sublist(1).join(' ');
      }
    }

    final registerRequest = RegisterRequest(
      email: emailController.text.trim(),
      password: passwordController.text,
      firstName: firstName,
      lastName: lastName,
      phone: phoneController.text.trim().isNotEmpty
          ? phoneController.text.trim()
          : null,
    );

    final response = await authProvider.register(registerRequest);

    if (response.success) {
      // Auto login after successful registration
      final loginRequest = LoginRequest(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      final loginResponse = await authProvider.login(loginRequest);

      if (loginResponse.success) {
        // Navigate to main page
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MainPage()),
          (route) => false,
        );
      } else {
        // If auto login fails, still navigate to main page
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MainPage()),
          (route) => false,
        );
      }
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
    Widget title = Text(
      'တွေ့ရတာ ဝမ်းသာပါတယ်',
      style: TextStyle(
          color: Colors.white,
          fontSize: 34.0,
          fontWeight: FontWeight.bold,
          shadows: [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.15),
              offset: Offset(0, 5),
              blurRadius: 10.0,
            )
          ]),
    );

    Widget subTitle = Padding(
        padding: const EdgeInsets.only(right: 56.0),
        child: Text(
          'နောင်ထပ်အသုံးပြုနိုင်ဖို့ အကောင့်အသစ် ဖန်တီးလိုက်ပါ။',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.0,
          ),
        ));

    Widget registerButton = Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Center(
          child: InkWell(
            onTap: authProvider.isLoading ? null : _handleRegister,
            child: Container(
              width: MediaQuery.of(context).size.width /
                  2, // Match Login button width exactly
              height: 60, // Match Login button height exactly - same as Login
              // Remove margin to match Login button exactly (Login button has no margin)
              decoration: BoxDecoration(
                // Use same gradient as Login button for consistency
                gradient: AppTheme.primaryGradient,
                boxShadow: [
                  // Match Login button shadow style exactly
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
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        "အကောင့်အသစ်ဖွင့်မယ်",
                        style: const TextStyle(
                          color: Color(0xfffefefe),
                          fontWeight:
                              FontWeight.w600, // Match Login button exactly
                          fontStyle: FontStyle.normal,
                          fontSize: 20.0, // Match Login button exactly
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );

    Widget registerForm = Container(
      width: MediaQuery.of(context).size.width,
      padding: const EdgeInsets.only(
        left: 32.0,
        right: 12.0,
        top: 8.0, // Add top padding for consistency
        bottom: 16.0, // Add bottom padding to ensure spacing is visible
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Full Name
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: TextFormField(
                controller: firstNameController,
                style: TextStyle(fontSize: 16.0),
                decoration: InputDecoration(
                  hintText: 'နာမည်အပြည့်အစုံ',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.0),
                ),
                validator: (value) =>
                    ValidationUtils.validateName(value, 'Full name'),
              ),
            ),
            // Email
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(fontSize: 16.0),
                decoration: InputDecoration(
                  hintText: 'အီးမေးလ်',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.0),
                ),
                validator: ValidationUtils.validateEmail,
              ),
            ),
            // Phone
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(fontSize: 16.0),
                decoration: InputDecoration(
                  hintText: 'လက်ရှိအသုံးပြုနေတဲ့ ဖုန်းနံပါတ်',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.0),
                ),
                validator: ValidationUtils.validatePhone,
              ),
            ),
            // Password
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: TextFormField(
                controller: passwordController,
                obscureText: _obscurePassword,
                style: TextStyle(fontSize: 16.0),
                decoration: InputDecoration(
                  hintText: 'လျို့ဝှက်နံပါတ်',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.0),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.grey,
                    ),
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
            // Confirm Password
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: TextFormField(
                controller: confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                style: TextStyle(fontSize: 16.0),
                decoration: InputDecoration(
                  hintText: 'လျို့ဝှက်နံပါတ် အတည်ပြုချက်',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.0),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                ),
                validator: (value) => ValidationUtils.validateConfirmPassword(
                    value, passwordController.text),
              ),
            ),
            // Sign Up Button - centered and matching Login button size exactly
            // Add significant spacing above button for better visual separation
            // Use Padding widget instead of SizedBox for more reliable spacing
            Padding(
              padding: const EdgeInsets.only(
                  top: 32.0,
                  bottom:
                      0), // Increased to 32.0 for significant visible spacing
              child: registerButton,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    Widget loginLink = Padding(
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

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: <Widget>[
              // Background
              Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/background.jpg'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: transparentYellow,
                ),
              ),
              // Scrollable content
              SafeArea(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 28.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: <Widget>[
                            const SizedBox(height: 60),
                            title,
                            const SizedBox(height: 8),
                            subTitle,
                            const SizedBox(height: 24),
                            registerForm,
                            const SizedBox(height: 16),
                            loginLink,
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Back button
              Positioned(
                top: 35,
                left: 5,
                child: SafeArea(
                  child: IconButton(
                    color: Colors.white,
                    icon: Icon(Icons.arrow_back),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
