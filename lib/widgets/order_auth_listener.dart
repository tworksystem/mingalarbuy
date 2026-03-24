import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/order_provider.dart';
import '../utils/logger.dart';

/// Listens to authentication state changes and clears order data
/// when user logs out or switches accounts
class OrderAuthListener extends StatefulWidget {
  final Widget child;

  const OrderAuthListener({
    super.key,
    required this.child,
  });

  @override
  State<OrderAuthListener> createState() => _OrderAuthListenerState();
}

class _OrderAuthListenerState extends State<OrderAuthListener> {
  String? _lastUserId;
  bool _lastAuthState = false;

  @override
  void initState() {
    super.initState();
    // Initialize with current auth state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      
      _lastAuthState = authProvider.isAuthenticated;
      _lastUserId = authProvider.user?.id.toString();
      
      // Handle initial state
      orderProvider.handleAuthStateChange(
        isAuthenticated: _lastAuthState,
        userId: _lastUserId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final isAuthenticated = authProvider.isAuthenticated;
        final currentUserId = authProvider.user?.id.toString();

        // Check if auth state or user ID changed
        if (_lastAuthState != isAuthenticated || _lastUserId != currentUserId) {
          // Update state
          _lastAuthState = isAuthenticated;
          _lastUserId = currentUserId;

          // Handle auth state change in OrderProvider
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final orderProvider = Provider.of<OrderProvider>(context, listen: false);
            orderProvider.handleAuthStateChange(
              isAuthenticated: isAuthenticated,
              userId: currentUserId,
            );
            
            Logger.info(
              'Order data cleared due to auth state change. Authenticated: $isAuthenticated, UserId: $currentUserId',
              tag: 'OrderAuthListener',
            );
          });
        }

        return widget.child;
      },
    );
  }
}

