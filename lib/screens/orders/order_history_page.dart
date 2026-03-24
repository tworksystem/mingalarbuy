import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/providers/order_provider.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/models/order.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/widgets/network_status_banner.dart';
import 'package:ecommerce_int2/services/connectivity_service.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/screens/product/all_products_page.dart';
import 'order_details_page.dart';
import 'package:intl/intl.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  _OrderHistoryPageState createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  OrderStatus? _selectedStatus;
  String _searchQuery = '';
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    // Removed "Shipped" category per UI requirements.
    _tabController = TabController(length: 4, vsync: this);

    // Load orders from local storage first (for offline support)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrdersFromStorage();

      // Sync orders from WooCommerce only if online
      final connectivityService = ConnectivityService();
      if (connectivityService.isConnected) {
        _syncOrdersFromWooCommerce();
      }
    });

    // Set up periodic sync (every 30 seconds when page is active)
    _startPeriodicSync();
  }

  /// Load orders from local storage (for offline support)
  void _loadOrdersFromStorage() {
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    // Orders are already loaded from storage in OrderProvider constructor
    // This ensures orders are displayed even when offline
    Logger.info('Orders loaded from storage: ${orderProvider.orders.length}',
        tag: 'OrderHistoryPage');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Start periodic sync to keep orders updated
  void _startPeriodicSync() {
    // Auto-refresh orders every 30 seconds
    Future.delayed(Duration(seconds: 30), () {
      if (mounted && !_isSyncing) {
        _syncOrdersFromWooCommerce();
        _startPeriodicSync(); // Continue periodic sync
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return NetworkStatusBanner(
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0.0,
          iconTheme: IconThemeData(color: darkGrey),
          title: Text(
            'Order History',
            style: TextStyle(
              color: darkGrey,
              fontWeight: FontWeight.w500,
              fontSize: 18.0,
            ),
          ),
          actions: [
            if (_searchQuery.isNotEmpty)
              IconButton(
                icon: Icon(Icons.clear),
                tooltip: 'Clear search',
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                  });
                },
              ),
            IconButton(
              icon: Icon(Icons.search),
              tooltip: 'Search orders',
              onPressed: _showSearchDialog,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'sync') {
                  _syncOrdersFromWooCommerce();
                } else if (value == 'filter') {
                  _showFilterDialog();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'sync',
                  child: Row(
                    children: [
                      _isSyncing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(mediumYellow),
                              ),
                            )
                          : Icon(Icons.sync, size: 20),
                      SizedBox(width: 12),
                      Text(_isSyncing ? 'Syncing...' : 'Sync Orders'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'filter',
                  child: Row(
                    children: [
                      Icon(Icons.filter_list, size: 20),
                      SizedBox(width: 12),
                      Text('Filter'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: mediumYellow,
            unselectedLabelColor: Colors.grey,
            indicatorColor: mediumYellow,
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Pending'),
              Tab(text: 'Processing'),
              Tab(text: 'Success'),
            ],
          ),
        ),
        body: Consumer<OrderProvider>(
          builder: (context, orderProvider, child) {
            if (orderProvider.isLoading) {
              return Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
                ),
              );
            }

            if (orderProvider.isEmpty) {
              return _buildEmptyState();
            }

            // Sort orders by date (newest first)
            final sortedOrders = List<Order>.from(orderProvider.orders)
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

            return TabBarView(
              controller: _tabController,
              children: [
                _buildOrderList(_getFilteredOrders(sortedOrders)),
                _buildOrderList(_getFilteredOrders(orderProvider.pendingOrders
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))),
                _buildOrderList(_getFilteredOrders(
                    orderProvider.processingOrders
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))),
                _buildOrderList(_getFilteredOrders(orderProvider.deliveredOrders
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Sync orders with WooCommerce backend
  Future<void> _syncOrdersFromWooCommerce() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final orderProvider = Provider.of<OrderProvider>(context, listen: false);
    final connectivityService = ConnectivityService();

    if (!authProvider.isAuthenticated || authProvider.user == null) {
      _showSnackBar('Please login to sync orders', isError: true);
      return;
    }

    // Check connectivity before syncing
    if (!connectivityService.isConnected) {
      _showSnackBar('No internet connection. Showing cached orders.',
          isError: false);
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      await orderProvider
          .syncOrdersWithWooCommerce(authProvider.user!.id.toString());
      if (mounted) {
        _showSnackBar('Orders synced successfully');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to sync orders: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 100,
            color: Colors.grey,
          ),
          SizedBox(height: 20),
          Text(
            'No orders yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: darkGrey,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Your orders will appear here',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Pull down to refresh and sync with server',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              // Navigate to Product Page (AllProductsPage)
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AllProductsPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: mediumYellow,
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            child: Text(
              'Start Shopping',
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

  Widget _buildOrderList(List<Order> orders) {
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _syncOrdersFromWooCommerce,
        color: mediumYellow,
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No orders in this category',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Pull down to refresh',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _syncOrdersFromWooCommerce,
      color: mediumYellow,
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return _buildOrderCard(order);
        },
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      shadowColor: Colors.black.withOpacity(0.1),
      child: InkWell(
        onTap: () => _navigateToOrderDetails(order),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _getStatusColor(order.status).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with Order ID and Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${order.id.replaceAll('WC-', '')}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: darkGrey,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              SizedBox(width: 4),
                              Text(
                                _formatDate(order.createdAt),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Single status badge - Show WooCommerce status if available, otherwise show mapped status
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _getStatusColor(order.status),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color:
                                _getStatusColor(order.status).withOpacity(0.3),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _getWooCommerceStatusText(order).isNotEmpty
                            ? _getWooCommerceStatusText(order)
                            : order.statusText,
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
                SizedBox(height: 16),
                // Order items preview
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.shopping_bag_outlined,
                                size: 18,
                                color: darkGrey,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '${order.itemCount} item${order.itemCount > 1 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: darkGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            order.formattedTotal,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: mediumYellow,
                            ),
                          ),
                        ],
                      ),
                      if (order.items.isNotEmpty) ...[
                        SizedBox(height: 8),
                        Divider(height: 1),
                        SizedBox(height: 8),
                        ...order.items.take(2).map((item) => Padding(
                              padding: EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.quantity}x ${item.product.name}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    item.formattedTotalPrice,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        if (order.items.length > 2)
                          Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              '+ ${order.items.length - 2} more item${order.items.length - 2 > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                // Sync indicator
                if (_getSyncTimestamp(order) != null) ...[
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.sync,
                        size: 12,
                        color: Colors.blue[400],
                      ),
                      SizedBox(width: 4),
                      Text(
                        _getSyncTimestamp(order)!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue[400],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
                // Additional info
                if (order.trackingNumber != null ||
                    order.paymentStatus != PaymentStatus.pending) ...[
                  SizedBox(height: 12),
                  if (order.trackingNumber != null)
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.green[200]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_shipping,
                            size: 18,
                            color: Colors.green[700],
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tracking Number',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  order.trackingNumber!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green[900],
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (order.paymentStatus != PaymentStatus.pending)
                    SizedBox(height: 8),
                  if (order.paymentStatus != PaymentStatus.pending)
                    Row(
                      children: [
                        Icon(
                          _getPaymentStatusIcon(order.paymentStatus),
                          size: 16,
                          color: _getPaymentStatusColor(order.paymentStatus),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Payment: ${_getPaymentStatusText(order.paymentStatus)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: _getPaymentStatusColor(order.paymentStatus),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
                // View details indicator
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 13,
                        color: mediumYellow,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: mediumYellow,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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

  IconData _getPaymentStatusIcon(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return Icons.check_circle;
      case PaymentStatus.pending:
        return Icons.pending;
      case PaymentStatus.failed:
        return Icons.error;
      case PaymentStatus.refunded:
        return Icons.refresh;
    }
  }

  Color _getPaymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return Colors.green;
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.failed:
        return Colors.red;
      case PaymentStatus.refunded:
        return Colors.grey;
    }
  }

  String _getPaymentStatusText(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.failed:
        return 'Failed';
      case PaymentStatus.refunded:
        return 'Refunded';
    }
  }

  /// Get WooCommerce status text from order metadata
  String _getWooCommerceStatusText(Order order) {
    if (order.metadata == null) return '';
    final wooStatus = order.metadata!['woocommerce_status'] ??
        order.metadata!['woocommerce_status_raw'] ??
        '';
    if (wooStatus.isEmpty) return '';

    // Format WooCommerce status for display (capitalize and replace hyphens)
    final formatted = wooStatus
        .toString()
        .split('-')
        .map((word) =>
            word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
    // Rename Delivered -> Success in history UI.
    if (formatted == 'Delivered') return 'Success';
    return formatted;
  }

  /// Get sync timestamp from order metadata
  String? _getSyncTimestamp(Order order) {
    if (order.metadata == null) return null;
    final syncTime =
        order.metadata!['sync_timestamp'] ?? order.metadata!['last_synced'];
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

  void _navigateToOrderDetails(Order order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailsPage(order: order),
      ),
    );
  }

  void _showSearchDialog() {
    final TextEditingController searchController =
        TextEditingController(text: _searchQuery);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.search, color: mediumYellow),
            SizedBox(width: 8),
            Text('Search Orders'),
          ],
        ),
        content: TextField(
          controller: searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search by order ID, product name, or city',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: Icon(Icons.search),
            suffixIcon: searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear),
                    onPressed: () {
                      searchController.clear();
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            // Update search query in real-time as user types
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _searchQuery = '';
              });
              Navigator.pop(context);
            },
            child: Text(
              'Clear',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _searchQuery = searchController.text.trim();
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: mediumYellow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Search',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.filter_list, color: mediumYellow),
            SizedBox(width: 8),
            Text('Filter Orders'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<OrderStatus?>(
                title: Text('All Orders'),
                value: null,
                groupValue: _selectedStatus,
                activeColor: mediumYellow,
                onChanged: (value) {
                  setState(() {
                    _selectedStatus = value;
                  });
                  Navigator.pop(context);
                },
              ),
              Divider(),
              ...OrderStatus.values
                  .where((status) => status != OrderStatus.shipped)
                  .map((status) {
                return RadioListTile<OrderStatus>(
                  title: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getStatusColor(status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(_getStatusText(status)),
                    ],
                  ),
                  value: status,
                  groupValue: _selectedStatus,
                  activeColor: mediumYellow,
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value;
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedStatus = null;
              });
              Navigator.pop(context);
            },
            child: Text(
              'Clear Filter',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: mediumYellow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Done',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.shipped:
        return 'Shipped';
      case OrderStatus.delivered:
        return 'Success';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.refunded:
        return 'Refunded';
    }
  }

  List<Order> _getFilteredOrders(List<Order> orders) {
    // Hide shipped orders from Order History UI per requirement.
    List<Order> filtered =
        orders.where((o) => o.status != OrderStatus.shipped).toList();

    // Apply search filter if query is not empty
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((order) {
        // Search by order ID (remove WC- prefix for search)
        final orderId = order.id.replaceAll('WC-', '').toLowerCase();
        if (orderId.contains(query)) {
          return true;
        }
        // Search by product names in order items
        final hasMatchingProduct = order.items
            .any((item) => item.product.name.toLowerCase().contains(query));
        if (hasMatchingProduct) {
          return true;
        }
        // Search by address
        if (order.shippingAddress.city.toLowerCase().contains(query) ||
            order.shippingAddress.state.toLowerCase().contains(query)) {
          return true;
        }
        return false;
      }).toList();
    }

    // Apply status filter if selected
    if (_selectedStatus != null) {
      filtered =
          filtered.where((order) => order.status == _selectedStatus).toList();
    }

    // Ensure sorted by date (newest first) - should already be sorted but double-check
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return filtered;
  }
}
