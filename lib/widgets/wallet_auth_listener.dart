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

  /// Avoids queuing a post-frame callback on every [didChangeDependencies] rebuild.
  bool _didScheduleDependenciesPostFrame = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // OLD CODE:
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (mounted) {
    //     _checkAuthAndLoadWallet();
    //   }
    // });
    if (!_didScheduleDependenciesPostFrame) {
      _didScheduleDependenciesPostFrame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkAuthAndLoadWallet();
        }
      });
    }
  }

  void _checkAuthAndLoadWallet() {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    if (authProvider.isAuthenticated && authProvider.user != null) {
      final userId = authProvider.user!.id.toString();

      if (_lastUserId != userId || !_hasInitialized) {
        final previousUserId = _lastUserId;
        _lastUserId = userId;
        _hasInitialized = true;

        if (previousUserId != null && previousUserId != userId) {
          Logger.info(
            'User account changed from $previousUserId to $userId, reloading wallet balance',
            tag: 'WalletAuthListener',
          );
        } else {
          Logger.info(
            'User authenticated, loading wallet balance for user: $userId',
            tag: 'WalletAuthListener',
          );
        }

        walletProvider
            .handleAuthStateChange(isAuthenticated: true, userId: userId)
            .catchError((e) {
              Logger.error(
                'Error loading wallet on auth: $e',
                tag: 'WalletAuthListener',
                error: e,
              );
            });
      }
    } else if (_lastUserId != null) {
      _lastUserId = null;
      _hasInitialized = false;
      walletProvider
          .handleAuthStateChange(isAuthenticated: false, userId: null)
          .catchError((e) {
            Logger.error(
              'Error clearing wallet on logout: $e',
              tag: 'WalletAuthListener',
              error: e,
            );
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final isAuthenticated = authProvider.isAuthenticated;
        final currentUserId = authProvider.user?.id.toString();

        if ((isAuthenticated && currentUserId != _lastUserId) ||
            (!isAuthenticated && _lastUserId != null) ||
            (isAuthenticated && !_hasInitialized)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _checkAuthAndLoadWallet();
            }
          });
        }

        return widget.child;
      },
    );
  }
}
