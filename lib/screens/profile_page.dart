import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/screens/faq_page.dart';
import 'package:ecommerce_int2/screens/payment/payment_page.dart';
import 'package:ecommerce_int2/screens/settings/settings_page.dart';
import 'package:ecommerce_int2/widgets/loyalty_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xffF9F9F9),
      body: SafeArea(
        top: true,
        child: Consumer2<PointProvider, AuthProvider>(
          builder: (context, pointProvider, authProvider, child) {
            final user = authProvider.user;
            final displayName = user != null
                ? '${user.firstName} ${user.lastName}'.trim()
                : 'Guest';

            return SingleChildScrollView(
              child: Padding(
                padding:
                    EdgeInsets.only(left: 16.0, right: 16.0, top: kToolbarHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            maxRadius: 48,
                            backgroundImage:
                                AssetImage('assets/profile.png'),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              displayName.isEmpty ? 'Loyalty Member' : displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (pointProvider.balance != null)
                            Text(
                              pointProvider.balance!.formattedBalance,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const LoyaltySummaryCard(),
                    Container(
                      margin: EdgeInsets.symmetric(vertical: 16.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: transparentYellow,
                            blurRadius: 4,
                            spreadRadius: 1,
                            offset: Offset(0, 1),
                          )
                        ],
                      ),
                      height: 150,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: <Widget>[
                            _buildQuickAction(
                              context,
                              label: 'Payment',
                              asset: 'assets/icons/card.png',
                              builder: (_) => PaymentPage(),
                            ),
                            _buildQuickAction(
                              context,
                              label: 'Support',
                              asset: 'assets/icons/contact_us.png',
                              builder: (_) => FaqPage(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ListTile(
                      title: Text('Settings'),
                      subtitle: Text('Privacy and logout'),
                      leading: Image.asset(
                        'assets/icons/settings.png',
                        fit: BoxFit.scaleDown,
                        width: 30,
                        height: 30,
                      ),
                      trailing: Icon(Icons.chevron_right, color: yellow),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SettingsPage())),
                    ),
                    Divider(),
                    ListTile(
                      title: Text('Help & Support'),
                      subtitle: Text('Help center and legal support'),
                      leading: Image.asset('assets/icons/support.png'),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: yellow,
                      ),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => FaqPage())),
                    ),
                    Divider(),
                    ListTile(
                      title: Text('FAQ'),
                      subtitle: Text('Questions and answers'),
                      leading: Image.asset('assets/icons/faq.png'),
                      trailing: Icon(Icons.chevron_right, color: yellow),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => FaqPage())),
                    ),
                    Divider(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    BuildContext context, {
    required String label,
    required String asset,
    required WidgetBuilder builder,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          icon: Image.asset(asset),
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: builder)),
        ),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        )
      ],
    );
  }
}
