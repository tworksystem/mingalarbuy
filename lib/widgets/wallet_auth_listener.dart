import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/wallet_provider.dart';
import '../utils/logger.dart';

/// Widget that listens to authentication state changes
/// and automatically loads wallet balance when user logs in
class WalletAuthListener extends StatefulWidget {
  final Widget child;

  const WalletAuthListener({super.key, required this.child});

  @override
  State<WalletAuthListener> createState() => _WalletAuthListenerState();
}

class _WalletAuthListenerState extends State<WalletAuthListener> {
  String? _lastUserId;
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAuthAndLoadWallet();
  }

  @override
  void didUpdateWidget(WalletAuthListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAuthAndLoadWallet();
  }

  void _checkAuthAndLoadWallet() {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    if (authProvider.isAuthenticated && authProvider.user != null) {
      final userId = authProvider.user!.id.toString();

      // Only load if this is a new user or first initialization
      if (_lastUserId != userId || !_hasInitialized) {
        _lastUserId = userId;
        _hasInitialized = true;

        Logger.info('User authenticated, loading wallet balance for user: $userId',
            tag: 'WalletAuthListener');

        // Load balance asynchronously without blocking UI
        walletProvider.handleAuthStateChange(
          isAuthenticated: true,
          userId: userId,
        ).catchError((e) {
          Logger.error('Error loading wallet on auth: $e',
              tag: 'WalletAuthListener', error: e);
        });
      }
    } else if (_lastUserId != null) {
      // User logged out
      _lastUserId = null;
      _hasInitialized = false;
      walletProvider.handleAuthStateChange(
        isAuthenticated: false,
        userId: null,
      ).catchError((e) {
        Logger.error('Error clearing wallet on logout: $e',
            tag: 'WalletAuthListener', error: e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

