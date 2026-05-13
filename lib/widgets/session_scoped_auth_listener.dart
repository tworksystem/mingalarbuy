import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/address_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/review_provider.dart';
import '../providers/spin_wheel_provider.dart';
import '../providers/wishlist_provider.dart';
import '../utils/logger.dart';

void _logAuthSyncError(String scope, Object e, StackTrace st) {
  Logger.error(
    '$scope: $e',
    tag: 'SessionScopedAuth',
    error: e,
    stackTrace: st,
  );
}

/// Keeps session-scoped local providers in sync with [AuthProvider] (logout + account switch).
class SessionScopedAuthListener extends StatefulWidget {
  const SessionScopedAuthListener({super.key, required this.child});

  final Widget child;

  @override
  State<SessionScopedAuthListener> createState() =>
      _SessionScopedAuthListenerState();
}

class _SessionScopedAuthListenerState extends State<SessionScopedAuthListener> {
  String? _lastUserId;
  bool _lastAuth = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncSessionScopedProviders();
      }
    });
  }

  void _syncSessionScopedProviders() {
    if (!mounted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final wishlist = Provider.of<WishlistProvider>(context, listen: false);
    final review = Provider.of<ReviewProvider>(context, listen: false);
    final address = Provider.of<AddressProvider>(context, listen: false);
    final spin = Provider.of<SpinWheelProvider>(context, listen: false);
    final cart = Provider.of<CartProvider>(context, listen: false);

    final isAuthenticated = auth.isAuthenticated;
    final userId = auth.user?.id.toString();

    if (!isAuthenticated || userId == null) {
      wishlist
          .handleAuthStateChange(isAuthenticated: false, userId: null)
          .catchError(
            (Object e, StackTrace st) =>
                _logAuthSyncError('Wishlist handleAuthStateChange', e, st),
          );
      review
          .handleAuthStateChange(isAuthenticated: false, userId: null)
          .catchError(
            (Object e, StackTrace st) =>
                _logAuthSyncError('Review handleAuthStateChange', e, st),
          );
      address
          .handleAuthStateChange(isAuthenticated: false, userId: null)
          .catchError(
            (Object e, StackTrace st) =>
                _logAuthSyncError('Address handleAuthStateChange', e, st),
          );
      spin
          .handleAuthStateChange(isAuthenticated: false, userId: null)
          .catchError(
            (Object e, StackTrace st) =>
                _logAuthSyncError('SpinWheel handleAuthStateChange', e, st),
          );
      cart
          .handleAuthStateChange(isAuthenticated: false, userId: null)
          .catchError(
            (Object e, StackTrace st) =>
                _logAuthSyncError('Cart handleAuthStateChange', e, st),
          );
      return;
    }

    wishlist
        .handleAuthStateChange(isAuthenticated: true, userId: userId)
        .catchError(
          (Object e, StackTrace st) =>
              _logAuthSyncError('Wishlist handleAuthStateChange', e, st),
        );
    review
        .handleAuthStateChange(isAuthenticated: true, userId: userId)
        .catchError(
          (Object e, StackTrace st) =>
              _logAuthSyncError('Review handleAuthStateChange', e, st),
        );
    address
        .handleAuthStateChange(isAuthenticated: true, userId: userId)
        .catchError(
          (Object e, StackTrace st) =>
              _logAuthSyncError('Address handleAuthStateChange', e, st),
        );
    spin
        .handleAuthStateChange(isAuthenticated: true, userId: userId)
        .catchError(
          (Object e, StackTrace st) =>
              _logAuthSyncError('SpinWheel handleAuthStateChange', e, st),
        );
    cart
        .handleAuthStateChange(isAuthenticated: true, userId: userId)
        .catchError(
          (Object e, StackTrace st) =>
              _logAuthSyncError('Cart handleAuthStateChange', e, st),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final isAuthenticated = authProvider.isAuthenticated;
        final currentUserId = authProvider.user?.id.toString();

        if (_lastAuth != isAuthenticated || _lastUserId != currentUserId) {
          _lastAuth = isAuthenticated;
          _lastUserId = currentUserId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _syncSessionScopedProviders();
            }
          });
        }

        return widget.child;
      },
    );
  }
}
