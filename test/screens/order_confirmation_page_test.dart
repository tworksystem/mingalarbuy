import 'package:ecommerce_int2/models/address.dart';
import 'package:ecommerce_int2/models/auth_user.dart';
import 'package:ecommerce_int2/models/cart_item.dart';
import 'package:ecommerce_int2/models/order.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/providers/order_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/screens/orders/order_confirmation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthProvider extends Mock with ChangeNotifier implements AuthProvider {}

class MockOrderProvider extends Mock with ChangeNotifier implements OrderProvider {}

class MockPointProvider extends Mock with ChangeNotifier implements PointProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Provider.debugCheckInvalidValueType = null;
    registerFallbackValue(<CartItem>[]);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(PaymentMethod.creditCard);
    registerFallbackValue(Address(
      id: 'fallback',
      userId: 'fallback',
      firstName: 'Fallback',
      lastName: 'User',
      addressLine1: '123 Street',
      city: 'City',
      state: 'State',
      postalCode: '12345',
      country: 'Country',
      phone: '000',
      createdAt: DateTime(2000),
    ));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('OrderConfirmationPage', () {
    testWidgets('places order and shows success state', (tester) async {
      final authProvider = MockAuthProvider();
      final orderProvider = MockOrderProvider();
      final pointProvider = MockPointProvider();
      final cartProvider = CartProvider();

      final product = Product('assets/placeholder.png', 'Sneakers', 'Comfort', 120);
      await cartProvider.addToCart(product, quantity: 1);

      final user = AuthUser(
        id: 42,
        email: 'user@example.com',
        firstName: 'Test',
        lastName: 'User',
        username: 'testuser',
      );

      final address = Address(
        id: 'addr-1',
        userId: user.id.toString(),
        firstName: 'Test',
        lastName: 'User',
        addressLine1: '123 Main St',
        city: 'Metropolis',
        state: 'NY',
        postalCode: '10001',
        country: 'USA',
        phone: '555-0100',
        createdAt: DateTime.now(),
      );

      final order = Order(
        id: 'WC-1000',
        userId: user.id.toString(),
        items: [
          OrderItem(
            product: product,
            quantity: 1,
            unitPrice: product.price,
          ),
        ],
        shippingAddress: address,
        billingAddress: address,
        subtotal: product.price,
        shippingCost: 0.0,
        tax: 0.0,
        discount: 0.0,
        total: product.price,
        status: OrderStatus.confirmed,
        paymentStatus: PaymentStatus.pending,
        paymentMethod: PaymentMethod.creditCard,
        createdAt: DateTime.now(),
      );

      when(() => authProvider.isAuthenticated).thenReturn(true);
      when(() => authProvider.user).thenReturn(user);
      when(() => pointProvider.currentBalance).thenReturn(0);
      when(() => pointProvider.loadBalance(any())).thenAnswer((_) async {});
      when(() => pointProvider.loadTransactions(any())).thenAnswer((_) async {});
      when(() => orderProvider.createOrder(
            userId: any(named: 'userId'),
            cartItems: any(named: 'cartItems'),
            shippingAddress: any(named: 'shippingAddress'),
            billingAddress: any(named: 'billingAddress'),
            paymentMethod: any(named: 'paymentMethod'),
            shippingCost: any(named: 'shippingCost'),
            tax: any(named: 'tax'),
            discount: any(named: 'discount'),
            notes: any(named: 'notes'),
            metadata: any(named: 'metadata'),
          )).thenAnswer((invocation) async {
        // capture invocation for debugging if needed
        return order;
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
            Provider<AuthProvider>.value(value: authProvider),
            Provider<OrderProvider>.value(value: orderProvider),
            Provider<PointProvider>.value(value: pointProvider),
          ],
          child: MaterialApp(
            home: OrderConfirmationPage(
              selectedShippingAddress: address,
              selectedBillingAddress: address,
              selectedPaymentMethod: PaymentMethod.creditCard,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Order Summary'), findsOneWidget);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pump();

      await tester.tap(find.text('Place Order'), warnIfMissed: false);
      await tester.pump(); // start loading
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => orderProvider.createOrder(
            userId: any(named: 'userId'),
            cartItems: any(named: 'cartItems'),
            shippingAddress: any(named: 'shippingAddress'),
            billingAddress: any(named: 'billingAddress'),
            paymentMethod: any(named: 'paymentMethod'),
            shippingCost: any(named: 'shippingCost'),
            tax: any(named: 'tax'),
            discount: any(named: 'discount'),
            notes: any(named: 'notes'),
            metadata: any(named: 'metadata'),
          )).called(1);

      await tester.pump(); // allow SnackBar animation
      expect(
        find.text('Order placed successfully! Order ID: ${order.id}'),
        findsOneWidget,
      );

      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(cartProvider.isEmpty, isTrue);

      verifyNever(() => pointProvider.loadBalance(any()));
      verifyNever(() => pointProvider.loadTransactions(any()));
    });

    testWidgets('shows empty state when cart is empty', (tester) async {
      final authProvider = MockAuthProvider();
      final orderProvider = MockOrderProvider();
      final pointProvider = MockPointProvider();
      final cartProvider = CartProvider();

      when(() => authProvider.isAuthenticated).thenReturn(true);
      when(() => authProvider.user).thenReturn(AuthUser(
        id: 1,
        email: 'user@example.com',
        firstName: 'Empty',
        lastName: 'Cart',
        username: 'emptycart',
      ));
      when(() => pointProvider.currentBalance).thenReturn(0);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
            Provider<AuthProvider>.value(value: authProvider),
            Provider<OrderProvider>.value(value: orderProvider),
            Provider<PointProvider>.value(value: pointProvider),
          ],
          child: const MaterialApp(
            home: OrderConfirmationPage(
              selectedPaymentMethod: PaymentMethod.creditCard,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(find.text('Add some items to your cart first'), findsOneWidget);
      verifyNever(() => orderProvider.createOrder(
            userId: any(named: 'userId'),
            cartItems: any(named: 'cartItems'),
            shippingAddress: any(named: 'shippingAddress'),
            billingAddress: any(named: 'billingAddress'),
            paymentMethod: any(named: 'paymentMethod'),
            shippingCost: any(named: 'shippingCost'),
            tax: any(named: 'tax'),
            discount: any(named: 'discount'),
            notes: any(named: 'notes'),
            metadata: any(named: 'metadata'),
          ));
    });

    testWidgets('rejects order when points balance insufficient', (tester) async {
      final authProvider = MockAuthProvider();
      final orderProvider = MockOrderProvider();
      final pointProvider = MockPointProvider();
      final cartProvider = CartProvider();

      final product = Product('assets/placeholder.png', 'Smartwatch', 'Feature rich', 200);
      await cartProvider.addToCart(product, quantity: 1);

      final user = AuthUser(
        id: 77,
        email: 'loyal@example.com',
        firstName: 'Loyal',
        lastName: 'Customer',
        username: 'loyal77',
      );

      final address = Address(
        id: 'addr-2',
        userId: user.id.toString(),
        firstName: 'Loyal',
        lastName: 'Customer',
        addressLine1: '456 Oak Street',
        city: 'Gotham',
        state: 'NJ',
        postalCode: '07001',
        country: 'USA',
        phone: '555-0200',
        createdAt: DateTime.now(),
      );

      when(() => authProvider.isAuthenticated).thenReturn(true);
      when(() => authProvider.user).thenReturn(user);
      when(() => pointProvider.currentBalance).thenReturn(250); // less than redeemed

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CartProvider>.value(value: cartProvider),
            Provider<AuthProvider>.value(value: authProvider),
            Provider<OrderProvider>.value(value: orderProvider),
            Provider<PointProvider>.value(value: pointProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: OrderConfirmationPage(
                selectedShippingAddress: address,
                selectedBillingAddress: address,
                selectedPaymentMethod: PaymentMethod.creditCard,
                redeemedPoints: 500,
                pointsDiscount: 5.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pump();

      await tester.tap(find.text('Place Order'), warnIfMissed: false);
      await tester.pump();

      expect(
        find.textContaining('Insufficient points'),
        findsOneWidget,
      );

      verifyNever(() => orderProvider.createOrder(
            userId: any(named: 'userId'),
            cartItems: any(named: 'cartItems'),
            shippingAddress: any(named: 'shippingAddress'),
            billingAddress: any(named: 'billingAddress'),
            paymentMethod: any(named: 'paymentMethod'),
            shippingCost: any(named: 'shippingCost'),
            tax: any(named: 'tax'),
            discount: any(named: 'discount'),
            notes: any(named: 'notes'),
            metadata: any(named: 'metadata'),
          ));
    });
  });
}

