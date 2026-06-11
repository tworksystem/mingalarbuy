import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../widgets/responsive_shell.dart';

class CustomBottomBar extends StatelessWidget {
  final TabController controller;

  const CustomBottomBar({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && ResponsiveShell.isWideLayout(context)) {
      return const SizedBox.shrink();
    }

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/home_icon.svg',
              fit: BoxFit.fitWidth,
            ),
            onPressed: () {
              controller.animateTo(0);
            },
          ),
          IconButton(
            icon: Image.asset('assets/icons/profile_icon.png'),
            onPressed: () {
              controller.animateTo(1);
            },
          ),
        ],
      ),
    );
  }
}

/// Side navigation rail for wide web/desktop layouts.
class WebSideNavigation extends StatelessWidget {
  const WebSideNavigation({
    super.key,
    required this.controller,
  });

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: controller.index,
      onDestinationSelected: controller.animateTo,
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: Text('Home'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: Text('Profile'),
        ),
      ],
    );
  }
}
