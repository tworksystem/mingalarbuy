import '../providers/cart_provider.dart';
import '../providers/in_app_notification_provider.dart';
import '../utils/logger.dart';
import 'woocommerce_service_cached.dart';

/// Clears cart, in-app notification state, and WooCommerce/product caches when
/// the auth session ends or switches to another user.
class AuthSessionCacheService {
  AuthSessionCacheService._();

  static CartProvider? _cartProvider;

  /// Called once from app root (e.g. after [MultiProvider]) so logout/switch
  /// can clear the live cart without relying on [BuildContext].
  static void registerCartProvider(CartProvider cart) {
    _cartProvider = cart;
  }

  /// Cart, in-app notifications, and global WooCommerce cache (via [CacheService]).
  static Future<void> clearAllSessionCaches() async {
    try {
      final cart = _cartProvider;
      if (cart != null) {
        await cart.clearCart();
      }
    } catch (e, st) {
      Logger.warning(
        'AuthSessionCacheService: cart clear failed: $e',
        tag: 'AuthSessionCache',
        error: e,
        stackTrace: st,
      );
    }

    try {
      await InAppNotificationProvider.instance.deleteAllNotifications();
    } catch (e, st) {
      Logger.warning(
        'AuthSessionCacheService: in-app notifications clear failed: $e',
        tag: 'AuthSessionCache',
        error: e,
        stackTrace: st,
      );
    }

    try {
      await WooCommerceServiceCached.clearCache();
    } catch (e, st) {
      Logger.warning(
        'AuthSessionCacheService: WooCommerce cache clear failed: $e',
        tag: 'AuthSessionCache',
        error: e,
        stackTrace: st,
      );
    }
  }
}
