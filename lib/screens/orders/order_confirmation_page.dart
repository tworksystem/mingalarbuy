import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/providers/order_provider.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/models/order.dart';
import 'package:ecommerce_int2/models/address.dart';
import 'package:ecommerce_int2/models/cart_item.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/screens/orders/order_details_page.dart';
import 'package:ecommerce_int2/screens/main/main_page.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/services/point_service.dart';
import 'package:ecommerce_int2/widgets/network_image_widget.dart';

class OrderConfirmationPage extends StatefulWidget {
  final Address? selectedShippingAddress;
  final Address? selectedBillingAddress;
  final PaymentMethod selectedPaymentMethod;
  final int redeemedPoints;
  final double pointsDiscount;
  final String contactPhone;
  final String? mobilePaymentProvider;
  final String? bankName;

  const OrderConfirmationPage({
    super.key,
    this.selectedShippingAddress,
    this.selectedBillingAddress,
    required this.selectedPaymentMethod,
    this.redeemedPoints = 0,
    this.pointsDiscount = 0.0,
    this.contactPhone = '',
    this.mobilePaymentProvider,
    this.bankName,
  });

  @override
  _OrderConfirmationPageState createState() => _OrderConfirmationPageState();
}

class _OrderConfirmationPageState extends State<OrderConfirmationPage> {
  bool _isCreatingOrder = false;
  Order? _createdOrder;

  Future<void> _onRefresh() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated) {
      await authProvider.refreshUser();
      final userId = authProvider.user?.id.toString();
      if (userId != null) {
        await Provider.of<PointProvider>(context, listen: false)
            .loadBalance(userId, forceRefresh: true);
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        iconTheme: IconThemeData(color: darkGrey),
        title: Text(
          'Order Confirmation',
          style: TextStyle(
            color: darkGrey,
            fontWeight: FontWeight.w500,
            fontSize: 18.0,
          ),
        ),
      ),
      body: Consumer<CartProvider>(
        builder: (context, cartProvider, child) {
          if (cartProvider.isEmpty) {
            return _buildEmptyCartState();
          }

          if (_createdOrder != null) {
            return _buildOrderSuccessState();
          }

          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPaymentSection(),
                  SizedBox(height: 20),
                  _buildOrderItems(cartProvider),
                  SizedBox(height: 30),
                  _buildPlaceOrderButton(cartProvider),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyCartState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 100,
            color: Colors.grey[300],
          ),
          SizedBox(height: 20),
          Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Add some items to your cart first',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
          SizedBox(height: 30),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => MainPage()),
              (route) => false,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: mediumYellow,
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            child: Text(
              'Continue Shopping',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSuccessState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                color: Colors.white,
                size: 60,
              ),
            ),
            SizedBox(height: 32),
            Text(
              'Order Placed Successfully!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: darkGrey,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              'Your order #${_createdOrder!.id} has been confirmed',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            if (widget.selectedPaymentMethod == PaymentMethod.mobilePayment ||
                widget.selectedPaymentMethod == PaymentMethod.bankTransfer)
              Text(
                'Please complete your payment within 15 minutes. '
                'After 15 minutes, your order may be cancelled automatically.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
              ),
            SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => MainPage()),
                      (route) => false,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      padding: EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: Text(
                      'Continue Shopping',
                      style: TextStyle(
                        color: darkGrey,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailsPage(order: _createdOrder!),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mediumYellow,
                      padding: EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: Text(
                      'View Order',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: mediumYellow, size: 20),
                SizedBox(width: 8),
                Text(
                  'Payment Method',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: darkGrey,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              _getPaymentMethodText(widget.selectedPaymentMethod),
              style: TextStyle(
                fontSize: 16,
                color: darkGrey,
              ),
            ),
            if (widget.selectedPaymentMethod == PaymentMethod.mobilePayment &&
                widget.mobilePaymentProvider != null) ...[
              SizedBox(height: 8),
              Text(
                'Mobile Payment: ${widget.mobilePaymentProvider}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
            if (widget.selectedPaymentMethod == PaymentMethod.bankTransfer &&
                widget.bankName != null) ...[
              SizedBox(height: 8),
              Text(
                'Bank: ${widget.bankName}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
            if (widget.contactPhone.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                'Contact Phone: ${widget.contactPhone}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItems(CartProvider cartProvider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Items',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: darkGrey,
              ),
            ),
            SizedBox(height: 12),
            ...cartProvider.items.map((item) => _buildOrderItem(item, cartProvider)),
          ],
        ),
      ),
    );
  }

  /// Professional Order Item with Creative Quantity Controls
  /// Features: Modern design, smooth animations, haptic feedback
  Widget _buildOrderItem(CartItem item, CartProvider cartProvider) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.grey[200],
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: NetworkImageWidget(
                imageUrl: item.product.image,
                width: 70,
                height: 70,
                fit: BoxFit.cover,
                fallbackAsset: 'assets/headphones.png',
              ),
            ),
          ),
          SizedBox(width: 12),
          // Product Info - Flexible to prevent overflow
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.product.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: darkGrey,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 6),
                // Creative Quantity Controls - Wrapped to prevent overflow
                Flexible(
                  child: _buildQuantityControls(item, cartProvider),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          // Price - Flexible to prevent overflow
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.formattedTotalPrice,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: mediumYellow,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  '${item.product.formattedPrice} each',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Creative Quantity Controls with Modern Design
  /// Features: Circular buttons, smooth animations, haptic feedback
  /// Uses Consumer to ensure real-time updates when cart changes
  /// Professional overflow handling with validated constraints and responsive design
  Widget _buildQuantityControls(CartItem item, CartProvider cartProvider) {
    return Consumer<CartProvider>(
      builder: (context, provider, child) {
        // Get the current item from cartProvider to ensure we have the latest quantity
        final currentItem = provider.getCartItem(item.product) ?? item;
        
        return LayoutBuilder(
          builder: (context, constraints) {
            // Ensure we have bounded constraints with proper fallback
            final maxWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : 200.0; // Fallback max width
            
            // Calculate quantity text width based on digit count
            // Single digit: ~12px, Double digit: ~20px, Triple digit: ~28px
            final quantityDigits = currentItem.quantity.toString().length;
            final quantityTextWidth = quantityDigits == 1 
                ? 12.0 
                : quantityDigits == 2 
                    ? 20.0 
                    : 28.0 + (quantityDigits - 3) * 8.0; // 28px for 3 digits, +8px per additional digit
            
            // Calculate ideal minimum required width
            // 2 buttons (32px each) + container padding (8px total) + quantity text (dynamic) + quantity padding (16px total)
            final idealMinWidth = 32.0 + 32.0 + 8.0 + quantityTextWidth + 16.0;
            
            // Calculate compact minimum width for very constrained spaces
            // Smaller buttons (28px each) + container padding (8px total) + quantity text (dynamic, scaled) + quantity padding (8px total)
            final compactQuantityTextWidth = quantityDigits == 1 
                ? 10.0 
                : quantityDigits == 2 
                    ? 16.0 
                    : 22.0 + (quantityDigits - 3) * 6.0; // Compact sizing for 3+ digits
            final compactMinWidth = 28.0 + 28.0 + 8.0 + compactQuantityTextWidth + 8.0;
            
            // Determine if we need compact mode
            final useCompactMode = maxWidth < idealMinWidth;
            
            // Use compact minimum if space is constrained, otherwise use ideal minimum
            // CRITICAL: Ensure minWidth is never greater than maxWidth
            final minWidth = useCompactMode 
                ? compactMinWidth.clamp(0.0, maxWidth) // Clamp to ensure min <= max
                : idealMinWidth.clamp(0.0, maxWidth); // Clamp to ensure min <= max
            
            // Responsive sizing based on available space
            final buttonSize = useCompactMode ? 28.0 : 32.0;
            final iconSize = useCompactMode ? 16.0 : 18.0;
            final fontSize = useCompactMode ? 14.0 : 16.0;
            
            // Responsive padding based on available space and digit count
            // For 3+ digits, reduce padding to accommodate text
            final basePadding = maxWidth < 100
                ? 4.0  // Minimal padding for very constrained spaces
                : maxWidth < 120 
                    ? 6.0  // Reduced padding for very small screens
                    : maxWidth < 140
                        ? 8.0  // Medium padding for small screens
                        : 12.0; // Standard padding for larger screens
            
            // Reduce padding for 3+ digits to prevent overflow
            final quantityPadding = quantityDigits >= 3 
                ? (basePadding * 0.7).clamp(4.0, basePadding) // 30% reduction for 3+ digits
                : basePadding;
            
            // Build the quantity controls with validated constraints
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                // CRITICAL: Always ensure minWidth <= maxWidth
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  minWidth: minWidth,
                ),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: mediumYellow.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: mediumYellow.withOpacity(0.1),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Decrease Button - Responsive size
                      SizedBox(
                        width: buttonSize,
                        height: buttonSize,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              if (currentItem.quantity > 1) {
                                await provider.updateQuantity(currentItem, currentItem.quantity - 1);
                              } else {
                                // Show confirmation for removing item
                                _showRemoveItemDialog(currentItem, provider);
                              }
                            },
                            borderRadius: BorderRadius.circular(buttonSize / 2),
                            child: Container(
                              decoration: BoxDecoration(
                                color: currentItem.quantity > 1
                                    ? Colors.red[50]
                                    : Colors.grey[100],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                currentItem.quantity > 1 ? Icons.remove : Icons.delete_outline,
                                size: iconSize,
                                color: currentItem.quantity > 1
                                    ? Colors.red[600]
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Quantity Display - Flexible width with overflow protection
                      Flexible(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: quantityPadding),
                          child: Text(
                            '${currentItem.quantity}',
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.bold,
                              color: darkGrey,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.visible, // Allow text to be visible
                            maxLines: 1,
                          ),
                        ),
                      ),
                      // Increase Button - Responsive size
                      SizedBox(
                        width: buttonSize,
                        height: buttonSize,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              await provider.updateQuantity(currentItem, currentItem.quantity + 1);
                            },
                            borderRadius: BorderRadius.circular(buttonSize / 2),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.add,
                                size: iconSize,
                                color: Colors.green[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Show confirmation dialog when removing item from cart
  void _showRemoveItemDialog(CartItem item, CartProvider cartProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Remove Item?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
        ),
        content: Text(
          'Are you sure you want to remove "${item.product.name}" from your cart?',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              HapticFeedback.mediumImpact();
              await cartProvider.removeFromCart(item.product);
            },
            child: Text(
              'Remove',
              style: TextStyle(
                color: Colors.red[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceOrderButton(CartProvider cartProvider) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isCreatingOrder ? null : () => _placeOrder(cartProvider),
        style: ElevatedButton.styleFrom(
          backgroundColor: mediumYellow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        child: _isCreatingOrder
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Confirming...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : Text(
                'Confirm',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Future<void> _placeOrder(CartProvider cartProvider) async {
    setState(() {
      _isCreatingOrder = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);

      if (!authProvider.isAuthenticated) {
        _showErrorSnackBar('Please login to place an order');
        return;
      }

      // Enhanced debugging and validation
      Logger.debug('Starting order creation process...', tag: 'OrderConfirmation');
      Logger.debug('User ID: ${authProvider.user!.id}', tag: 'OrderConfirmation');
      Logger.debug('Cart Items: ${cartProvider.items.length}', tag: 'OrderConfirmation');
      Logger.debug('Payment Method: ${widget.selectedPaymentMethod.name}',
          tag: 'OrderConfirmation');

      // Validate cart items
      if (cartProvider.items.isEmpty) {
        _showErrorSnackBar('Your cart is empty. Please add items to cart.');
        return;
      }

      final userId = authProvider.user!.id.toString();
      final pointProvider = Provider.of<PointProvider>(context, listen: false);

      final shippingAddress =
          widget.selectedShippingAddress ?? _buildPlaceholderAddress(authProvider);
      final billingAddress =
          widget.selectedBillingAddress ?? shippingAddress;

      Logger.debug(
        'Shipping Address: ${shippingAddress.firstName} ${shippingAddress.lastName}',
        tag: 'OrderConfirmation',
      );

      // Step 1: Validate points redemption (if points were selected)
      if (widget.redeemedPoints > 0 && widget.pointsDiscount > 0) {
        // Validate redemption amount before proceeding
        final cartTotal = cartProvider.totalPrice;
        
        // Check if user has enough points
        if (pointProvider.currentBalance < widget.redeemedPoints) {
          _showErrorSnackBar(
              'Insufficient points. You have ${pointProvider.currentBalance} points, but need ${widget.redeemedPoints} points.');
          return;
        }

        // Validate redemption limits
        if (!PointService.isValidRedemptionAmount(
          widget.redeemedPoints,
          cartTotal,
          pointProvider.currentBalance,
        )) {
          final maxPoints = PointService.calculateMaxRedeemablePoints(cartTotal);
          _showErrorSnackBar(
              'Invalid points redemption. Maximum $maxPoints points allowed (${PointService.maxRedemptionPercent}% of order total).');
          return;
        }

        Logger.info('Points redemption validated: ${widget.redeemedPoints} points (-\$${widget.pointsDiscount.toStringAsFixed(2)})',
            tag: 'OrderConfirmation');
      }

      // Step 2: Create order with discount applied
      final Map<String, dynamic> metadata = {};
      if (widget.redeemedPoints > 0 && widget.pointsDiscount > 0) {
        metadata.addAll({
          'redeemed_points': widget.redeemedPoints,
          'points_discount': widget.pointsDiscount,
          'points_redeemed_at': DateTime.now().toIso8601String(),
        });
      }

      if (widget.contactPhone.isNotEmpty) {
        metadata['contact_phone'] = widget.contactPhone;
      }
      if (widget.selectedPaymentMethod == PaymentMethod.mobilePayment &&
          widget.mobilePaymentProvider != null) {
        metadata['mobile_payment_provider'] = widget.mobilePaymentProvider;
      }
      if (widget.selectedPaymentMethod == PaymentMethod.bankTransfer &&
          widget.bankName != null) {
        metadata['bank_name'] = widget.bankName;
      }

      final order = await orderProvider.createOrder(
        userId: userId,
        cartItems: cartProvider.items,
        shippingAddress: shippingAddress,
        billingAddress: billingAddress,
        paymentMethod: widget.selectedPaymentMethod,
        shippingCost: 0.0,
        tax: 0.0,
        discount: widget.pointsDiscount, // Apply points discount to order total
        notes: (widget.redeemedPoints > 0)
            ? 'Points redeemed: ${widget.redeemedPoints} points (-\$${widget.pointsDiscount.toStringAsFixed(2)})'
            : null,
        metadata: metadata.isNotEmpty ? metadata : null,
      );

      // Step 3: Redeem points AFTER successful order creation (with order ID)
      if (order != null && widget.redeemedPoints > 0 && widget.pointsDiscount > 0) {
        try {
          Logger.info('Redeeming ${widget.redeemedPoints} points for order ${order.id}',
              tag: 'OrderConfirmation');

          // Phase 1 UX: Give immediate feedback; do not block the user on long sync retries.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Syncing points...'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          
          // Extract WooCommerce order ID from order metadata if available
          final wooOrderId = order.metadata?['woocommerce_id']?.toString();
          final orderIdForPoints = wooOrderId ?? order.id;

          // Redeem points with order ID (wait for backend sync to ensure points are deducted)
          final redemptionSuccess = await PointService.redeemPoints(
            userId: userId,
            points: widget.redeemedPoints,
            description: 'Points redeemed for order #${order.id}',
            orderId: orderIdForPoints,
            waitForSync: true, // Wait for backend sync to ensure points are deducted
          );
          
          // Update point provider state after redemption
          if (redemptionSuccess) {
            // Phase 1: non-blocking post-sync refresh (reconcile in background)
            unawaited(pointProvider.loadBalance(userId, notifyLoading: false));
            unawaited(pointProvider.loadTransactions(userId, notifyLoading: false));
          }

          if (!redemptionSuccess) {
            // Points redemption failed after order creation
            // This is a critical issue - order was created but points weren't redeemed
            Logger.error(
                'CRITICAL: Order ${order.id} created but points redemption failed. Points: ${widget.redeemedPoints}',
                tag: 'OrderConfirmation');
            
            // Show warning but don't fail the order
            _showErrorSnackBar(
                'Order created successfully, but points redemption failed. Please contact support with order #${order.id}');
            
            // Still proceed with order success flow
          }
        } catch (e, stackTrace) {
          Logger.error('Error redeeming points after order creation: $e',
              tag: 'OrderConfirmation', error: e, stackTrace: stackTrace);
          
          // Show warning but don't fail the order
          _showErrorSnackBar(
              'Order created successfully, but points redemption encountered an error. Please contact support.');
        }
      }

      // Step 4: Refresh point balance & history so UI shows latest points
      if (order != null) {
        try {
          // Phase 1: background reconcile only (avoid blocking UX)
          unawaited(
            pointProvider.loadBalance(
              userId,
              forceRefresh: true,
              notifyLoading: false,
            ),
          );
          unawaited(pointProvider.loadTransactions(userId, notifyLoading: false));
        } catch (e, stackTrace) {
          Logger.error(
            'Error refreshing point balance after order creation: $e',
            tag: 'OrderConfirmation',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      if (order != null) {
        print('✅ Order created successfully: ${order.id}');

        // For mobile payment / bank transfer, gently remind user immediately
        if (widget.selectedPaymentMethod == PaymentMethod.mobilePayment ||
            widget.selectedPaymentMethod == PaymentMethod.bankTransfer) {
          // Show a lightweight dialog; ignore errors if context is gone
          // (wrapped in Future.microtask to avoid setState timing issues)
          Future.microtask(() {
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (ctx) {
                return AlertDialog(
                  title: Text('Payment Reminder'),
                  content: Text(
                    'Please transfer the payment within 15 minutes. '
                    'If payment is not received in time, your order may be cancelled automatically.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('OK'),
                    ),
                  ],
                );
              },
            );
          });
        }

        // Clear cart after successful order
        await cartProvider.clearCart();

        setState(() {
          _createdOrder = order;
        });

        _showSuccessSnackBar(
            'Order placed successfully! Order ID: ${order.id}');
      } else {
        print('❌ Order creation failed - returned null');
        
        // Get error message from order provider
        final orderProvider = Provider.of<OrderProvider>(context, listen: false);
        final errorMessage = orderProvider.errorMessage ?? 
            'Failed to create order. Please check your internet connection and try again.';
        
        _showErrorSnackBar(errorMessage);
      }
    } catch (e, stackTrace) {
      print('❌ Order creation error: $e');
      print('Stack trace: $stackTrace');
      
      // Extract user-friendly error message
      String errorMessage = 'Order creation failed';
      if (e.toString().contains('WooCommerce')) {
        errorMessage = 'Unable to connect to store. Please check your internet connection.';
      } else if (e.toString().contains('validation')) {
        errorMessage = 'Please check your order details and try again.';
      } else if (e.toString().contains('cart')) {
        errorMessage = 'Your cart appears to be empty. Please add items to cart.';
      } else {
        errorMessage = e.toString().replaceAll('Exception: ', '').trim();
        if (errorMessage.isEmpty || errorMessage == 'null') {
          errorMessage = 'Order creation failed. Please try again.';
        }
      }
      
      _showErrorSnackBar(errorMessage);
    } finally {
      setState(() {
        _isCreatingOrder = false;
      });
    }
  }

  /// When user doesn't want to provide an address, create a minimal placeholder
  /// so WooCommerce order creation still succeeds.
  Address _buildPlaceholderAddress(AuthProvider authProvider) {
    final user = authProvider.user!;
    final phone = widget.contactPhone.isNotEmpty
        ? widget.contactPhone
        : (user.phone ?? '');
    return Address(
      id: 'ADDR-NOADDRESS-${DateTime.now().millisecondsSinceEpoch}',
      userId: user.id.toString(),
      firstName: user.firstName.isNotEmpty ? user.firstName : 'Customer',
      lastName: user.lastName.isNotEmpty ? user.lastName : '',
      addressLine1: 'N/A',
      city: 'N/A',
      state: 'N/A',
      postalCode: '00000',
      country: (user.billingCountry?.isNotEmpty == true) ? user.billingCountry! : 'MM',
      phone: phone,
      email: user.email,
      createdAt: DateTime.now(),
      notes: 'No address provided by customer',
    );
  }

  String _getPaymentMethodText(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.creditCard:
        return 'Credit Card';
      case PaymentMethod.debitCard:
        return 'Debit Card';
      case PaymentMethod.mobilePayment:
        return 'Mobile Payment';
      case PaymentMethod.bankTransfer:
        return 'Bank Transfer';
      case PaymentMethod.cashOnDelivery:
        return 'Cash on Delivery';
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
