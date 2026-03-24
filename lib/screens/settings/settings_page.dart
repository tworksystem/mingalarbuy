import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/custom_background.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/screens/auth/welcome_back_page.dart';
import 'package:ecommerce_int2/screens/settings/change_password_page.dart';
import 'package:ecommerce_int2/screens/settings/legal_about_page.dart';
import 'package:ecommerce_int2/screens/settings/notifications_settings_page.dart';
import 'package:ecommerce_int2/services/global_keys.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// Handle logout with proper state cleanup and navigation
  Future<void> _handleLogout(BuildContext context) async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign Out'),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Perform logout
      await authProvider.logout();
      
      // Navigate to login page using global navigator key for reliability
      // This ensures navigation works even if the current context is disposed
      final navigatorContext = AppKeys.navigatorKey.currentContext ?? context;
      Navigator.of(navigatorContext).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => WelcomeBackPage()),
        (route) => false,
      );
    } catch (e) {
      // Show error if logout fails
      final scaffoldContext = AppKeys.scaffoldMessengerKey.currentContext ?? context;
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        SnackBar(
          content: Text('Sign out failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: MainBackground(),
      child: Scaffold(
        appBar: AppBar(
          iconTheme: IconThemeData(
            color: Colors.black,
          ),
          backgroundColor: Colors.transparent,
          title: Text(
            'Settings',
            style: TextStyle(color: darkGrey),
          ),
          elevation: 0, systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        body: SafeArea(
          bottom: true,
          child: LayoutBuilder(
                      builder:(builder,constraints)=> AppPullToRefresh(
                        onRefresh: () async {
                          final authProvider = Provider.of<AuthProvider>(context, listen: false);
                          await authProvider.refreshUser();
                        },
                        child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Padding(
              padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'General',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 18.0),
                    ),
                  ),
                   ListTile(
                    title: Text('Notifications'),
                     leading: Image.asset(
                       'assets/icons/notifications.png',
                       fit: BoxFit.scaleDown,
                       width: 30,
                       height: 30,
                     ),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => NotificationSettingsPage())),
                  ),
                   ListTile(
                    title: Text('Legal & About'),
                     leading: Image.asset(
                       'assets/icons/legal.png',
                       fit: BoxFit.scaleDown,
                       width: 30,
                       height: 30,
                     ),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => LegalAboutPage())),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                    child: Text(
                      'Account',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 18.0),
                    ),
                  ),
                  ListTile(
                    title: Text('Change Password'),
                    leading: Image.asset(
                      'assets/icons/change_pass.png',
                      fit: BoxFit.scaleDown,
                      width: 30,
                      height: 30,
                    ),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ChangePasswordPage())),
                  ),
                  ListTile(
                    title: Text('Sign out'),
                    leading: Image.asset(
                      'assets/icons/sign_out.png',
                      fit: BoxFit.scaleDown,
                      width: 30,
                      height: 30,
                    ),
                    onTap: () => _handleLogout(context),
                  ),
                  
                ],
              ),
            ),
                        ),
                      ),
                      )
          ),
        ),
      ),
    );
  }
}
