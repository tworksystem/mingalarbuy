import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/providers/order_provider.dart';
import 'package:ecommerce_int2/models/order.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:intl/intl.dart';
import 'package:ecommerce_int2/widgets/network_image_widget.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';

class OrderDetailsPage extends StatefulWidget {
  final Order order;

  const OrderDetailsPage({super.key, required this.order});

  @override
  _OrderDetailsPageState createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        iconTheme: IconThemeData(color: darkGrey),
        title: Text(
          'Order Details',
          style: TextStyle(
            color: darkGrey,
            fontWeight: FontWeight.w500,
            fontSize: 18.0,
          ),
        ),
        actions: [
          if (widget.order.canCancel)
            TextButton(
              onPressed: _showCancelDialog,
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
      body: AppPullToRefresh(
        onRefresh: () async {
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          if (authProvider.isAuthenticated && authProvider.user != null) {
            final userId = authProvider.user!.id.toString();
            await Provider.of<OrderProvider>(context, listen: false)
                .syncOrdersWithWooCommerce(userId);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOrderHeader(),
              SizedBox(height: 20),
              _buildOrderItems(),
              SizedBox(height: 20),
              _buildShippingAddress(),
              SizedBox(height: 20),
              _buildBillingAddress(),
              SizedBox(height: 20),
              _buildOrderSummary(),
              SizedBox(height: 20),
              _buildPaymentInfo(),
              if (widget.order.trackingNumber != null) ...[
                SizedBox(height: 20),
                _buildTrackingInfo(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderHeader() {
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order #${widget.order.id}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: darkGrey,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getStatusColor(widget.order.status),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _getStatusColor(widget.order.status).withOpacity(0.3),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    _getWooCommerceStatusText(widget.order).isNotEmpty
                        ? _getWooCommerceStatusText(widget.order)
                        : widget.order.statusText,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Placed on ${_formatDate(widget.order.createdAt)}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            if (widget.order.updatedAt != null) ...[
              SizedBox(height: 4),
              Text(
                'Updated on ${_formatDate(widget.order.updatedAt!)}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
            // Show WooCommerce sync info if available
            if (_getSyncTimestamp(widget.order) != null) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.sync,
                    size: 14,
                    color: Colors.blue[400],
                  ),
                  SizedBox(width: 6),
                  Text(
                    _getSyncTimestamp(widget.order)!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[400],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (_getWooCommerceOrderId(widget.order) != null) ...[
                    SizedBox(width: 8),
                    Text(
                      '• WC ID: ${_getWooCommerceOrderId(widget.order)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItems() {
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
            ...widget.order.items.map((item) => _buildOrderItem(item)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItem(OrderItem item) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: NetworkImageWidget(
                imageUrl: item.product.image,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                fallbackAsset: 'assets/headphones.png',
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: darkGrey,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  'Qty: ${item.quantity}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            item.formattedTotalPrice,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: mediumYellow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShippingAddress() {
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
                Icon(
                  Icons.local_shipping,
                  color: mediumYellow,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Shipping Address',
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
              widget.order.shippingAddress.fullName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: darkGrey,
              ),
            ),
            SizedBox(height: 4),
            Text(
              widget.order.shippingAddress.completeAddress,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingAddress() {
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
                Icon(
                  Icons.receipt,
                  color: mediumYellow,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Billing Address',
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
              widget.order.billingAddress.fullName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: darkGrey,
              ),
            ),
            SizedBox(height: 4),
            Text(
              widget.order.billingAddress.completeAddress,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
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
              'Order Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: darkGrey,
              ),
            ),
            SizedBox(height: 12),
            _buildSummaryRow('Subtotal', widget.order.formattedSubtotal),
            _buildSummaryRow('Shipping',
                '${widget.order.shippingCost.toStringAsFixed(2)} Ks'),
            _buildSummaryRow('Tax', '${widget.order.tax.toStringAsFixed(2)} Ks'),
            if (widget.order.discount > 0)
              _buildSummaryRow(
                  'Discount', '-${widget.order.discount.toStringAsFixed(2)} Ks',
                  isDiscount: true),
            Divider(),
            _buildSummaryRow('Total', widget.order.formattedTotal,
                isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isDiscount = false, bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isDiscount ? Colors.green : darkGrey,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal
                  ? mediumYellow
                  : (isDiscount ? Colors.green : darkGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo() {
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
                Icon(
                  Icons.payment,
                  color: mediumYellow,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Payment Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: darkGrey,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            _buildInfoRow('Payment Method', widget.order.paymentMethodText),
            _buildInfoRow('Payment Status', widget.order.paymentStatusText),
            if (widget.order.paymentId != null)
              _buildInfoRow('Payment ID', widget.order.paymentId!),
            // Show WooCommerce payment info if available
            if (_getWooCommercePaymentInfo(widget.order).isNotEmpty) ...[
              SizedBox(height: 8),
              Divider(),
              SizedBox(height: 8),
              ..._getWooCommercePaymentInfo(widget.order).entries.map((entry) {
                return _buildInfoRow(entry.key, entry.value);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingInfo() {
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
                Icon(
                  Icons.track_changes,
                  color: Colors.green,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Tracking Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: darkGrey,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            _buildInfoRow('Tracking Number', widget.order.trackingNumber!),
            if (widget.order.shippedAt != null)
              _buildInfoRow('Shipped On', _formatDate(widget.order.shippedAt!)),
            if (widget.order.deliveredAt != null)
              _buildInfoRow(
                  'Delivered On', _formatDate(widget.order.deliveredAt!)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: darkGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.processing:
        return Colors.purple;
      case OrderStatus.shipped:
        return Colors.green;
      case OrderStatus.delivered:
        return Colors.green[700]!;
      case OrderStatus.cancelled:
        return Colors.red;
      case OrderStatus.refunded:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today, ${DateFormat('h:mm a').format(date)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday, ${DateFormat('h:mm a').format(date)}';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE, MMM d').format(date);
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  /// Get WooCommerce status text from order metadata
  String _getWooCommerceStatusText(Order order) {
    if (order.metadata == null) return '';
    final wooStatus = order.metadata!['woocommerce_status'] ?? 
                     order.metadata!['woocommerce_status_raw'] ?? '';
    if (wooStatus.isEmpty) return '';
    
    // Format WooCommerce status for display (capitalize and replace hyphens)
    return wooStatus
        .toString()
        .split('-')
        .map((word) => word.isEmpty 
            ? '' 
            : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Get WooCommerce order ID from metadata
  String? _getWooCommerceOrderId(Order order) {
    if (order.metadata == null) return null;
    final wooId = order.metadata!['woocommerce_id'];
    return wooId?.toString();
  }

  /// Get sync timestamp from order metadata
  String? _getSyncTimestamp(Order order) {
    if (order.metadata == null) return null;
    final syncTime = order.metadata!['sync_timestamp'] ?? 
                    order.metadata!['last_synced'];
    if (syncTime == null) return null;
    
    try {
      final syncDate = DateTime.parse(syncTime);
      final now = DateTime.now();
      final difference = now.difference(syncDate);
      
      if (difference.inMinutes < 1) {
        return 'Just synced';
      } else if (difference.inMinutes < 60) {
        return 'Synced ${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return 'Synced ${difference.inHours}h ago';
      } else {
        return 'Synced ${difference.inDays}d ago';
      }
    } catch (e) {
      return null;
    }
  }

  /// Get WooCommerce payment info from metadata
  Map<String, String> _getWooCommercePaymentInfo(Order order) {
    final info = <String, String>{};
    if (order.metadata == null) return info;

    // Get WooCommerce payment method if available
    final wooPaymentMethod = order.metadata!['woocommerce_payment_method'];
    if (wooPaymentMethod != null && wooPaymentMethod.toString().isNotEmpty) {
      info['WooCommerce Payment Method'] = wooPaymentMethod.toString();
    }

    // Get WooCommerce payment status
    final wooPaymentStatus = order.metadata!['woocommerce_payment_status'];
    if (wooPaymentStatus != null && wooPaymentStatus.toString().isNotEmpty) {
      info['WooCommerce Payment Status'] = wooPaymentStatus.toString();
    }

    // Get WooCommerce order status
    if (_getWooCommerceStatusText(order).isNotEmpty) {
      info['WooCommerce Status'] = _getWooCommerceStatusText(order);
    }

    return info;
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Order'),
        content: Text(
            'Are you sure you want to cancel this order? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('No'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final orderProvider =
                  Provider.of<OrderProvider>(context, listen: false);
              final success = await orderProvider.cancelOrder(widget.order.id);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Order cancelled successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.pop(context); // Go back to order history
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to cancel order'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }
}
