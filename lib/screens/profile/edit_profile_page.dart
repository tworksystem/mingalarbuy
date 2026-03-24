import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/auth_user.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/utils/validation_utils.dart';
import 'package:ecommerce_int2/widgets/modern_loading_indicator.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class EditProfilePage extends StatefulWidget {
  final AuthUser user;

  const EditProfilePage({super.key, required this.user});

  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _usernameController;
  // Billing address fields
  late TextEditingController _billingAddress1Controller;
  late TextEditingController _billingAddress2Controller;
  late TextEditingController _billingCityController;
  late TextEditingController _billingPostcodeController;
  late TextEditingController _billingCountryController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.user.firstName);
    _lastNameController = TextEditingController(text: widget.user.lastName);
    _phoneController = TextEditingController(text: widget.user.phone ?? '');
    _emailController = TextEditingController(text: widget.user.email);
    _usernameController = TextEditingController(text: widget.user.username);
    _billingAddress1Controller = TextEditingController();
    _billingAddress2Controller = TextEditingController();
    _billingCityController =
        TextEditingController(text: widget.user.billingCity ?? '');
    _billingPostcodeController = TextEditingController();
    _billingCountryController =
        TextEditingController(text: widget.user.billingCountry ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _billingAddress1Controller.dispose();
    _billingAddress2Controller.dispose();
    _billingCityController.dispose();
    _billingPostcodeController.dispose();
    _billingCountryController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      final phoneValue = _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : null;
      print(
          'DEBUG: EditProfilePage - Phone controller value: "${_phoneController.text}"');
      print('DEBUG: EditProfilePage - Phone value to update: "$phoneValue"');

      final updatedUser = widget.user.copyWith(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: phoneValue,
      );

      print(
          'DEBUG: EditProfilePage - Updated user phone: ${updatedUser.phone}');

      // Build optional billing map for Woo update
      final billingExtra = {
        if (_billingAddress1Controller.text.trim().isNotEmpty)
          'address_1': _billingAddress1Controller.text.trim(),
        if (_billingAddress2Controller.text.trim().isNotEmpty)
          'address_2': _billingAddress2Controller.text.trim(),
        if (_billingCityController.text.trim().isNotEmpty)
          'city': _billingCityController.text.trim(),
        if (_billingPostcodeController.text.trim().isNotEmpty)
          'postcode': _billingPostcodeController.text.trim(),
        if (_billingCountryController.text.trim().isNotEmpty)
          'country': _billingCountryController.text.trim(),
      };

      // Update names + local phone via WP/me + local store
      final response = await authProvider.updateProfile(updatedUser);

      // Also persist billing to WooCommerce (address + phone)
      final billingResponse = await authProvider.updateBilling(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: phoneValue,
        billingExtra: billingExtra.isEmpty ? null : billingExtra,
      );

      if (response.success || billingResponse.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(billingResponse.success
                ? billingResponse.message
                : response.message),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(billingResponse.message.isNotEmpty
                ? billingResponse.message
                : response.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile'),
        backgroundColor: mediumYellow,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isLoading)
            Padding(
              padding: EdgeInsets.all(16.0),
              child: ModernLoadingIndicator(
                size: 20,
                color: Colors.white,
              ),
            )
          else
            TextButton(
              onPressed: _saveProfile,
              child: Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [mediumYellow.withValues(alpha: 0.1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: AppPullToRefresh(
          onRefresh: () async {
            if (!mounted) return;
            setState(() {});
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Profile Header
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: mediumYellow,
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 15),
                      Text(
                        'Update Your Profile',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Keep your information up to date',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 30),

                // Form Fields
                _buildFormSection(
                  title: 'Personal Information',
                  children: [
                    _buildTextField(
                      controller: _firstNameController,
                      label: 'First Name',
                      icon: Icons.person,
                      validator: (value) =>
                          ValidationUtils.validateName(value, 'First name'),
                    ),
                    SizedBox(height: 16),
                    _buildTextField(
                      controller: _lastNameController,
                      label: 'Last Name',
                      icon: Icons.person_outline,
                      validator: (value) =>
                          ValidationUtils.validateName(value, 'Last name'),
                    ),
                    SizedBox(height: 16),
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email',
                      icon: Icons.email,
                      enabled: false, // Email usually can't be changed
                      validator: null,
                    ),
                    SizedBox(height: 16),
                    _buildTextField(
                      controller: _usernameController,
                      label: 'Username',
                      icon: Icons.alternate_email,
                      enabled: false, // Username is read-only
                      validator: null,
                    ),
                    SizedBox(height: 16),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                      validator: ValidationUtils.validatePhone,
                    ),
                  ],
                ),

                SizedBox(height: 30),

                // Billing Address Section
                _buildFormSection(
                  title: 'Billing Address',
                  children: [
                    _buildTextField(
                      controller: _billingAddress1Controller,
                      label: 'Address Line 1',
                      icon: Icons.home,
                    ),
                    SizedBox(height: 16),
                    _buildTextField(
                      controller: _billingAddress2Controller,
                      label: 'Address Line 2 (Optional)',
                      icon: Icons.home_outlined,
                    ),
                    SizedBox(height: 16),
                    _buildTextField(
                      controller: _billingCityController,
                      label: 'City',
                      icon: Icons.location_city,
                    ),
                    SizedBox(height: 16),
                    _buildTextField(
                      controller: _billingPostcodeController,
                      label: 'Postcode',
                      icon: Icons.local_post_office,
                      keyboardType: TextInputType.number,
                    ),
                    SizedBox(height: 16),
                    _buildTextField(
                      controller: _billingCountryController,
                      label: 'Country (e.g., MM, US)',
                      icon: Icons.public,
                    ),
                  ],
                ),

                SizedBox(height: 30),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mediumYellow,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 3,
                    ),
                    child: _isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ModernLoadingIndicator(
                                size: 20,
                                color: Colors.white,
                              ),
                              SizedBox(width: 10),
                              Text('Saving...'),
                            ],
                          )
                        : Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                SizedBox(height: 20),

                // Change Password Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _showChangePasswordDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: mediumYellow,
                      side: BorderSide(color: mediumYellow, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Change Password',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      readOnly: !enabled, // Make it read-only when disabled
      validator: validator,
      style: TextStyle(
        fontSize: 16,
        color: enabled ? Colors.black87 : Colors.grey[700],
        fontWeight: enabled ? FontWeight.normal : FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          color: enabled ? mediumYellow : Colors.grey[500],
        ),
        suffixIcon: !enabled
            ? Padding(
                padding: EdgeInsets.all(12.0),
                child: Tooltip(
                  message: 'Read-only field',
                  child: Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: Colors.grey[600],
                  ),
                ),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: enabled ? Colors.grey[300]! : Colors.grey[400]!,
            width: enabled ? 1 : 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: enabled ? Colors.grey[300]! : Colors.grey[400]!,
            width: enabled ? 1 : 1.5,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.grey[400]!,
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: mediumYellow, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red, width: 2),
        ),
        filled: true,
        fillColor: enabled ? Colors.grey[50] : Colors.grey[150],
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrentPassword = true;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock, color: mediumYellow),
              SizedBox(width: 10),
              Text('Change Password'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentPasswordController,
                  obscureText: obscureCurrentPassword,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: Icon(Icons.lock_outline, color: mediumYellow),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureCurrentPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: mediumYellow,
                      ),
                      onPressed: () {
                        setState(() {
                          obscureCurrentPassword = !obscureCurrentPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: mediumYellow, width: 2),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: newPasswordController,
                  obscureText: obscureNewPassword,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: Icon(Icons.lock, color: mediumYellow),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNewPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: mediumYellow,
                      ),
                      onPressed: () {
                        setState(() {
                          obscureNewPassword = !obscureNewPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: mediumYellow, width: 2),
                    ),
                  ),
                  validator: ValidationUtils.validatePassword,
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: Icon(Icons.lock, color: mediumYellow),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: mediumYellow,
                      ),
                      onPressed: () {
                        setState(() {
                          obscureConfirmPassword = !obscureConfirmPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: mediumYellow, width: 2),
                    ),
                  ),
                  validator: (value) => ValidationUtils.validateConfirmPassword(
                    value,
                    newPasswordController.text,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newPasswordController.text !=
                    confirmPasswordController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('New passwords do not match'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                // Close the Change Password dialog safely
                if (mounted) {
                  Navigator.of(context).pop();
                }

                // Show loading dialog (non-blocking)
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => AlertDialog(
                    content: Row(
                      children: [
                        ModernLoadingIndicator(
                          size: 30,
                          color: mediumYellow,
                        ),
                        SizedBox(width: 20),
                        Text('Changing password...'),
                      ],
                    ),
                  ),
                );

                try {
                  final authProvider =
                      Provider.of<AuthProvider>(context, listen: false);

                  final response = await authProvider.changePassword(
                    currentPassword: currentPasswordController.text,
                    newPassword: newPasswordController.text,
                  );

                  // Close loading dialog safely
                  final nav = Navigator.of(context, rootNavigator: true);
                  if (nav.canPop()) nav.pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(response.message),
                      backgroundColor:
                          response.success ? Colors.green : Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  // Close loading dialog safely
                  final nav = Navigator.of(context, rootNavigator: true);
                  if (nav.canPop()) nav.pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('An error occurred. Please try again.'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: mediumYellow,
                foregroundColor: Colors.white,
              ),
              child: Text('Change Password'),
            ),
          ],
        ),
      ),
    );
  }
}
