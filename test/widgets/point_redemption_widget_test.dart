import 'dart:convert';

import 'package:ecommerce_int2/models/point_transaction.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/widgets/point_redemption_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PointProvider> buildPointProvider(
    PointBalance balance,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final balanceJson = json.encode(balance.toJson());
    await prefs.setString('user_point_balance', balanceJson);
    await prefs.setString('user_point_balance${balance.userId}', balanceJson);
    final provider = PointProvider();
    await provider.loadBalance(balance.userId);
    return provider;
  }

  Future<CartProvider> buildCartProvider({
    required Product product,
    int quantity = 1,
  }) async {
    final cartProvider = CartProvider();
    await cartProvider.addToCart(product, quantity: quantity);
    return cartProvider;
  }

  group('PointRedemptionWidget visibility', () {
    testWidgets('renders nothing when user has no redeemable points',
        (tester) async {
      final pointProvider = await buildPointProvider(
        PointBalance(
          userId: 'user-zero',
          currentBalance: 50,
          lifetimeEarned: 200,
          lifetimeRedeemed: 100,
          lifetimeExpired: 0,
          lastUpdated: DateTime.now(),
        ),
      );

      final cartProvider = await buildCartProvider(
        product: Product('assets/placeholder.png', 'Item', 'Description', 100),
        quantity: 1,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PointProvider>.value(value: pointProvider),
            ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PointRedemptionWidget(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Redeem Points'), findsNothing);
    });
  });

  group('PointRedemptionWidget interactions', () {
    testWidgets('quick select applies the expected discount',
        (tester) async {
      final balance = PointBalance(
        userId: 'user-rich',
        currentBalance: 5000,
        lifetimeEarned: 8000,
        lifetimeRedeemed: 2000,
        lifetimeExpired: 0,
        lastUpdated: DateTime.now(),
      );

      final pointProvider = await buildPointProvider(balance);
      final cartProvider = await buildCartProvider(
        product: Product('assets/placeholder.png', 'Headphones', 'Premium', 100),
        quantity: 2,
      );

      int? redeemedPoints;
      double? redeemedDiscount;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PointProvider>.value(value: pointProvider),
            ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PointRedemptionWidget(
                onPointsRedeemed: (points, discount) {
                  redeemedPoints = points;
                  redeemedDiscount = discount;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Redeem Points'), findsOneWidget);
      expect(find.text('${balance.currentBalance} pts'), findsOneWidget);

      await tester.tap(find.text('Use All'));
      await tester.pump(); // allow setState
      await tester.pump(const Duration(milliseconds: 300)); // snack bar animation

      expect(redeemedPoints, 5000);
      expect(redeemedDiscount, 50.0);
      expect(
        find.textContaining('-\$50.00'),
        findsOneWidget,
      );
    });

    testWidgets('custom input enables apply button only for valid amounts',
        (tester) async {
      final balance = PointBalance(
        userId: 'user-custom',
        currentBalance: 2000,
        lifetimeEarned: 5000,
        lifetimeRedeemed: 1000,
        lifetimeExpired: 0,
        lastUpdated: DateTime.now(),
      );

      final pointProvider = await buildPointProvider(balance);
      final cartProvider = await buildCartProvider(
        product: Product('assets/placeholder.png', 'Sneakers', 'Comfort', 80),
        quantity: 1,
      );

      int? redeemedPoints;
      double? redeemedDiscount;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PointProvider>.value(value: pointProvider),
            ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PointRedemptionWidget(
                onPointsRedeemed: (points, discount) {
                  redeemedPoints = points;
                  redeemedDiscount = discount;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      // Enter below minimum value - button should remain disabled
      await tester.enterText(textFieldFinder, '50');
      await tester.pump();

      final applyButtonFinder = find.widgetWithText(ElevatedButton, 'Apply');
      final ElevatedButton disabledButton =
          tester.widget<ElevatedButton>(applyButtonFinder);
      expect(disabledButton.onPressed, isNull);

      // Enter valid amount and apply
      await tester.enterText(textFieldFinder, '400');
      await tester.pump();

      await tester.tap(applyButtonFinder);
      await tester.pump(); // allow setState
      await tester.pump(const Duration(milliseconds: 300));

      expect(redeemedPoints, 400);
      expect(redeemedDiscount, 4.0);
      expect(find.textContaining('-\$4.00'), findsOneWidget);

      // Clearing should reset state
      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(find.textContaining('-\$4.00'), findsNothing);
    });
  });
}

