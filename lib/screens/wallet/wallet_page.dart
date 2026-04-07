import 'package:ecommerce_int2/api_service.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/user.dart';
import 'package:ecommerce_int2/widgets/modern_loading_indicator.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/wallet_provider.dart';
import 'package:ecommerce_int2/screens/payment_history_page.dart';
import 'package:ecommerce_int2/screens/request_money/request_amount_page.dart';
import 'package:ecommerce_int2/screens/request_money/request_page.dart';
import 'package:ecommerce_int2/screens/send_money/send_page.dart';
import 'package:ecommerce_int2/widgets/withdrawal_dialog.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  _WalletPageState createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with TickerProviderStateMixin {
  late AnimationController animController;
  late Animation<double> openOptions;

  List<User> users = [];
  String? _lastRefreshedUserId;
  DateTime? _lastRefreshTime;

  Future<void> getUsers() async {
    var temp = await ApiService.getUsers(nrUsers: 5);
    setState(() {
      users = temp;
    });
  }

  @override
  void initState() {
    animController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 300));
    openOptions = Tween(begin: 0.0, end: 300.0).animate(animController);
    getUsers();
    
    super.initState();
    
    // Load wallet balance when page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshWalletBalance();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh balance when page becomes visible again (with debounce)
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated && authProvider.user != null) {
      final userId = authProvider.user!.id.toString();
      
      // Only refresh if user changed or it's been more than 1 second since last refresh
      final shouldRefresh = _lastRefreshedUserId != userId ||
          _lastRefreshTime == null ||
          DateTime.now().difference(_lastRefreshTime!) > const Duration(seconds: 1);
      
      if (shouldRefresh) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _refreshWalletBalance();
          }
        });
      }
    }
  }
  
  @override
  void activate() {
    super.activate();
    // Called when the route is pushed onto the navigator or becomes active
    // Refresh balance when page becomes active (e.g., after dialog closes)
    // BUT: Use a longer delay to avoid race with a recent in-app wallet credit
    // WalletProvider skips overwriting balances updated within the last few seconds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Longer delay so any pending balance write can finish before refresh
        // The WalletProvider will skip the refresh if balance was recently updated
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _refreshWalletBalance();
          }
        });
      }
    });
  }

  /// Refresh wallet balance
  void _refreshWalletBalance() {
    if (!mounted) return;
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    
    if (authProvider.isAuthenticated && authProvider.user != null) {
      final userId = authProvider.user!.id.toString();
      _lastRefreshedUserId = userId;
      _lastRefreshTime = DateTime.now();
      
      // Always refresh to get latest balance
      walletProvider.loadBalance(userId, forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey[100],
      child: SafeArea(
        child: LayoutBuilder(
          builder: (builder, constraints) => AppPullToRefresh(
            onRefresh: () async {
              _refreshWalletBalance();
              await getUsers();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Align(
                        alignment: Alignment(1, 0),
                        child: SizedBox(
                          height: kTextTabBarHeight,
                          child: IconButton(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => PaymentHistoryPage())),
                            icon: SvgPicture.asset(
                              'assets/icons/reload_icon.svg',
                              colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn),
                            ),
                          ),
                        )),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'Payment',
                          style: TextStyle(
                            color: darkGrey,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        CloseButton()
                      ],
                    ),
                  ),
                  Text('Current account balance'),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Consumer<WalletProvider>(
                      // Remove stable key to allow Consumer to rebuild properly
                      // The Consumer will rebuild automatically when provider notifies
                      builder: (context, walletProvider, child) {
                        // Verify we're using the same provider instance
                        final providerInstance = WalletProvider.instance;
                        final isSameInstance = walletProvider.hashCode == providerInstance.hashCode;
                        
                        if (kDebugMode && !isSameInstance) {
                          print('⚠️ WARNING: Consumer provider instance mismatch! Consumer: ${walletProvider.hashCode}, Instance: ${providerInstance.hashCode}');
                        }
                        
                        // Show loading only if balance is null and still loading
                        // Using same style as Hot Deals loading
                        if (walletProvider.isLoading && walletProvider.balance == null) {
                          return const Center(
                            child: ModernLoadingIndicatorSmall(
                              color: mediumYellow,
                            ),
                          );
                        }
                        
                        // Get balance value (default to 0.00 if null)
                        // Use currentBalance getter which handles null properly
                        final balanceValue = walletProvider.currentBalance;
                        final balance = balanceValue.toStringAsFixed(2);
                        
                        // Debug logging (only in debug mode)
                        if (kDebugMode) {
                          print('💰 WalletPage Consumer rebuild - Balance: \$$balance (provider balance: ${walletProvider.balance?.currentBalance}, isLoading: ${walletProvider.isLoading}, instance: ${walletProvider.hashCode})');
                        }
                        
                        // Use a unique key based on balance to force rebuild
                        // AnimatedSwitcher provides smooth transition when balance changes
                        return Column(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                              child: Row(
                                key: ValueKey('balance_$balance'), // Unique key based on balance value ensures proper animation
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Text(
                                    balance,
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 8.0),
                                  Text(
                                    'Ks',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 24,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Withdraw button
                            ElevatedButton.icon(
                              onPressed: balanceValue > 0
                                  ? () async {
                                      final result = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => const WithdrawalDialog(),
                                      );
                                      if (result == true) {
                                        // Refresh balance after withdrawal
                                        _refreshWalletBalance();
                                      }
                                    }
                                  : null,
                              icon: const Icon(Icons.account_balance_wallet),
                              label: const Text('Withdraw Funds'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: mediumYellow,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    height: 100,
                    child: Stack(
                      children: <Widget>[
                        Center(
                          child: Container(
                            width: openOptions.value,
                            height: 80,
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(45)),
                                border: Border.all(color: yellow, width: 1.5)),
                            child: openOptions.value < 300
                                ? Container()
                                : Align(
                                    alignment: Alignment(0, 0),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: <Widget>[
                                        InkWell(
                                            onTap: () => Navigator.of(context)
                                                .push(MaterialPageRoute(
                                                    builder: (_) =>
                                                        SendPage())),
                                            child: Text('Pay')),
                                        InkWell(
                                            onTap: () => Navigator.of(context)
                                                .push(MaterialPageRoute(
                                                    builder: (_) =>
                                                        RequestPage())),
                                            child: Text('Request')),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        Center(
                            child: CustomPaint(
                                painter: YellowDollarButton(),
                                child: GestureDetector(
                                  onTap: () {
                                    animController.addListener(() {
                                      setState(() {});
                                    });
                                    if (openOptions.value == 300) {
                                      animController.reverse();
                                    } else {
                                      animController.forward();
                                    }
                                  },
                                  child: SizedBox(
                                      width: 110,
                                      height: 110,
                                      child: Center(
                                          child: Text('Ks',
                                              style: TextStyle(
                                                  color: Color.fromRGBO(
                                                      255, 255, 255, 0.5),
                                                  fontSize: 32)))),
                                )))
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                        openOptions.value > 0 ? '' : 'Tap to pay / request',
                        style: TextStyle(fontSize: 10)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Quick Money Request'),
                  ),
                  Flexible(
                      child: Center(
                    child: users.isEmpty
                        ? CupertinoActivityIndicator()
                        : Container(
                            height: 150,
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0),
                                    child: IconButton(
                                      onPressed: () {},
                                      icon: Container(
                                        decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.black,
                                            ),
                                            borderRadius: BorderRadius.all(
                                                Radius.circular(10))),
                                        child: Icon(Icons.add),
                                      ),
                                    ),
                                  ),
                                  ...users
                                      .map((user) => InkWell(
                                            onTap: () => Navigator.of(context)
                                                .push(MaterialPageRoute(
                                                    builder: (_) =>
                                                        RequestAmountPage(
                                                            user))),
                                            child: Container(
                                                width: 100,
                                                height: 200,
                                                margin: const EdgeInsets.only(
                                                    left: 8.0, right: 8.0),
                                                decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.all(
                                                            Radius.circular(
                                                                5))),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: <Widget>[
                                                    CircleAvatar(
                                                      maxRadius: 24,
                                                      backgroundImage:
                                                          NetworkImage(user
                                                              .picture
                                                              .thumbnail),
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets
                                                              .fromLTRB(
                                                          4.0, 16.0, 4.0, 0.0),
                                                      child: Text(
                                                          '${user.name.first} ${user.name.last}',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                            fontSize: 14.0,
                                                          )),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 8.0),
                                                      child: Text(
                                                        user.phone,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                            fontSize: 10),
                                                      ),
                                                    ),
                                                  ],
                                                )),
                                          ))
                                      ,
                                ]),
                          ),
                  )),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Hot Deals'),
                  ),
                  Flexible(
                    child: Container(
                      height: 232,
                      color: Color(0xffFAF1E2),
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 10,
                        itemBuilder: (_, index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8.0),
                          padding: const EdgeInsets.all(16.0),
                          width: 140,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Icon(Icons.tab),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Text('Dicount Voucher',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 16.0,
                                        fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Text('10% off on any pizzahut products',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10.0,
                                    )),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class YellowDollarButton extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    double height = size.height;
    double width = size.width;

    canvas.drawCircle(Offset(width / 2, height / 2), height / 2,
        Paint()..color = Color.fromRGBO(253, 184, 70, 0.2));
    canvas.drawCircle(Offset(width / 2, height / 2), height / 2 - 4,
        Paint()..color = Color.fromRGBO(253, 184, 70, 0.5));
    canvas.drawCircle(Offset(width / 2, height / 2), height / 2 - 12,
        Paint()..color = Color.fromRGBO(253, 184, 70, 1));
    canvas.drawCircle(Offset(width / 2, height / 2), height / 2 - 16,
        Paint()..color = Color.fromRGBO(255, 255, 255, 0.1));
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
