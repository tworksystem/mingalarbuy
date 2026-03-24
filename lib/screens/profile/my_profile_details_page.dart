import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/custom_background.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/screens/profile/edit_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class MyProfileDetailsPage extends StatefulWidget {
  const MyProfileDetailsPage({super.key});

  @override
  _MyProfileDetailsPageState createState() => _MyProfileDetailsPageState();
}

class _MyProfileDetailsPageState extends State<MyProfileDetailsPage> {
  @override
  void initState() {
    super.initState();
    // Refresh user data when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.refreshUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (!authProvider.isAuthenticated || authProvider.user == null) {
          return Scaffold(
            appBar: AppBar(
              iconTheme: IconThemeData(color: Colors.black),
              backgroundColor: Colors.transparent,
              title: Text(
                'My Profile',
                style: TextStyle(color: darkGrey),
              ),
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.dark,
            ),
            body: Center(
              child: Text('Please login to view your profile'),
            ),
          );
        }

        final user = authProvider.user!;

        return CustomPaint(
          painter: MainBackground(),
          child: Scaffold(
            appBar: AppBar(
              iconTheme: IconThemeData(
                color: Colors.black,
              ),
              backgroundColor: Colors.transparent,
              title: Text(
                'My Profile',
                style: TextStyle(color: darkGrey),
              ),
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.dark,
            ),
            body: SafeArea(
              bottom: true,
              child: LayoutBuilder(
                builder: (builder, constraints) => RefreshIndicator(
                  onRefresh: () async {
                    // Refresh user data
                    await authProvider.refreshUser();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.only(
                            top: 24.0, left: 24.0, right: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // Personal Information Section
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                'Personal Information',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18.0),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  ListTile(
                                    title: Text('Name'),
                                    subtitle: Text(
                                      (user.firstName.isNotEmpty ||
                                              user.lastName.isNotEmpty)
                                          ? '${user.firstName} ${user.lastName}'
                                              .trim()
                                          : (user.displayName.isNotEmpty
                                              ? user.displayName
                                              : 'Not set'),
                                    ),
                                    leading: Image.asset(
                                        'assets/icons/profile_icon.png',
                                        width: 30,
                                        height: 30),
                                    trailing: Icon(Icons.chevron_right,
                                        color: yellow),
                                    onTap: () async {
                                      final result =
                                          await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              EditProfilePage(user: user),
                                        ),
                                      );
                                      if (result == true) {
                                        await authProvider.refreshUser();
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  Divider(height: 1),
                                  ListTile(
                                    title: Row(
                                      children: [
                                        Text('Email'),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.lock_outline,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      user.email,
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    leading: Image.asset(
                                        'assets/icons/comment.png',
                                        width: 30,
                                        height: 30),
                                    trailing: Icon(
                                      Icons.lock_outline,
                                      color: Colors.grey[500],
                                      size: 18,
                                    ),
                                    enabled: false,
                                  ),
                                  Divider(height: 1),
                                  ListTile(
                                    title: Text('Phone'),
                                    subtitle: Text(
                                        (user.phone ?? '').trim().isNotEmpty
                                            ? user.phone!.trim()
                                            : 'Not set'),
                                    leading: Image.asset(
                                        'assets/icons/contact_us.png',
                                        width: 30,
                                        height: 30),
                                    trailing: Icon(Icons.chevron_right,
                                        color: yellow),
                                    onTap: () async {
                                      final result =
                                          await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              EditProfilePage(user: user),
                                        ),
                                      );
                                      if (result == true) {
                                        await authProvider.refreshUser();
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  Divider(height: 1),
                                  ListTile(
                                    title: Row(
                                      children: [
                                        Text('Username'),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.lock_outline,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      user.username.isNotEmpty
                                          ? user.username
                                          : 'Not set',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    leading: Image.asset(
                                        'assets/icons/list.png',
                                        width: 30,
                                        height: 30),
                                    trailing: Icon(
                                      Icons.lock_outline,
                                      color: Colors.grey[500],
                                      size: 18,
                                    ),
                                    enabled: false,
                                  ),
                                ],
                              ),
                            ),
                            // Address Information Section
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 24.0, bottom: 8.0),
                              child: Text(
                                'Address Information',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18.0),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  ListTile(
                                    title: Text('Billing Address'),
                                    subtitle:
                                        Text(user.billingAddress ?? 'Not set'),
                                    leading: Image.asset(
                                        'assets/icons/address_home.png',
                                        width: 30,
                                        height: 30),
                                    trailing: Icon(Icons.chevron_right,
                                        color: yellow),
                                    onTap: () async {
                                      final result =
                                          await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              EditProfilePage(user: user),
                                        ),
                                      );
                                      if (result == true) {
                                        await authProvider.refreshUser();
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  if ((user.billingCity ?? '').isNotEmpty) ...[
                                    Divider(height: 1),
                                    ListTile(
                                      title: Text('City'),
                                      subtitle: Text(user.billingCity!),
                                      leading: Image.asset(
                                          'assets/icons/country.png',
                                          width: 30,
                                          height: 30),
                                      trailing: Icon(Icons.chevron_right,
                                          color: yellow),
                                      onTap: () async {
                                        final result =
                                            await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                EditProfilePage(user: user),
                                          ),
                                        );
                                        if (result == true) {
                                          await authProvider.refreshUser();
                                          setState(() {});
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Additional Information section under My Profile has been removed
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

}
