# WooCommerce Integration - T-Work Commerce

## 🚀 Professional WooCommerce REST API Integration

This Flutter app (**T-Work Commerce**) is professionally integrated with **TworkSystem** e-commerce store using WooCommerce REST API v3.

### 🏪 Store Information

- **Store Name:** TworkSystem
- **Website:** https://www.tworksystem.com
- **API Version:** WooCommerce REST API v3
- **Package Name:** `ecommerce_int2`
- **App Name:** T-Work Commerce
- **Package ID:** `com.twork.ecommerce`

---

## 📋 Features Implemented

### ✅ Core Features

1. **WooCommerce REST API Integration**
   - Full REST API v3 implementation
   - Secure authentication with Consumer Key & Secret
   - Real-time product data synchronization
   - Comprehensive error handling with retry mechanisms

2. **Product Management**
   - Display all products from TworkSystem
   - Featured products showcase
   - Product details with images, prices, ratings
   - Stock status tracking
   - Sale/Discount badges
   - Category filtering
   - Advanced search functionality

3. **Offline Support & Caching**
   - Multi-layer caching mechanism (memory + persistent)
   - Persistent storage with SharedPreferences
   - Offline product viewing
   - Cache expiration management (1 hour default)
   - Automatic cache refresh
   - Graceful fallback to cached data on network errors

4. **Error Handling & Recovery**
   - Comprehensive error handling with custom exceptions
   - Network error detection
   - Timeout management (30 seconds default)
   - Graceful fallback to cached data
   - User-friendly error messages
   - Retry logic with exponential backoff

5. **UI/UX Features**
   - Pull-to-refresh functionality
   - Loading states with indicators
   - Product image caching with `cached_network_image`
   - Responsive grid layout
   - Product detail pages
   - Sale badges and featured tags
   - Rating stars display
   - Tab-based navigation (All Products / Featured)

---

## 🏗️ Architecture & Code Structure

### Clean Architecture Pattern

```
lib/
├── config/
│   └── woocommerce_config.dart          # API configuration & credentials
├── models/
│   ├── woocommerce_product.dart         # Product model
│   ├── woocommerce_order.dart           # Order model
│   └── woocommerce_category.dart        # Category model
├── services/
│   ├── woocommerce_service.dart         # API service layer
│   ├── woocommerce_service_cached.dart  # Cached service variant
│   └── product_repository.dart         # Repository pattern with caching
├── widgets/
│   └── woocommerce_product_list.dart    # Product list widget
├── screens/
│   └── main/
│       └── woocommerce_page.dart        # Main products page
└── utils/
    └── app_config.dart                  # App-wide configuration
```

### Key Classes

#### 1. **WooCommerceConfig** (`lib/config/woocommerce_config.dart`)
- Centralized API configuration
- Consumer Key & Secret management
- Endpoint definitions
- Cache settings (1 hour expiration, 100 max items)
- URL building utilities
- Authentication parameter helpers

#### 2. **WooCommerceService** (`lib/services/woocommerce_service.dart`)
- HTTP API calls with proper error handling
- Authentication via query parameters
- Comprehensive error handling with custom exceptions
- Response parsing and validation
- Connection testing
- Timeout management (30 seconds)
- Debug logging

#### 3. **ProductRepository** (`lib/services/product_repository.dart`)
- Data management layer with Repository pattern
- Multi-layer caching (memory + persistent)
- Offline support with cache fallback
- Search functionality (cache-first strategy)
- Cache expiration management
- Force refresh capability

#### 4. **WooCommerceProduct** (`lib/models/woocommerce_product.dart`)
- Complete product data model
- JSON serialization/deserialization
- Helper methods (pricing, ratings, stock status)
- Image URL handling
- Category and tag management

#### 5. **AppConfig** (`lib/utils/app_config.dart`)
- App-wide configuration
- Base URLs (WooCommerce API + WordPress API)
- Backend server configuration
- Performance settings
- Feature flags
- Security settings

---

## 🔐 API Credentials

The following credentials are configured in `lib/config/woocommerce_config.dart`:

```dart
baseUrl: 'https://tworksystem.com'
consumerKey: 'YOUR_CONSUMER_KEY_HERE'
consumerSecret: 'YOUR_CONSUMER_SECRET_HERE'
```

**Alternative Configuration:** The app also uses `lib/utils/app_config.dart` for some settings:

```dart
baseUrl: 'https://www.tworksystem.com/wp-json/wc/v3'
consumerKey: 'YOUR_CONSUMER_KEY_HERE'
consumerSecret: 'YOUR_CONSUMER_SECRET_HERE'
```

**Security Note:** In production, these should be stored in environment variables or secure storage. Never commit actual credentials to version control.

---

## 📦 Dependencies

All required dependencies are configured in `pubspec.yaml`:

```yaml
dependencies:
  http: ^1.5.0                      # HTTP requests
  shared_preferences: ^2.2.2        # Local storage for caching
  cached_network_image: ^3.4.1       # Image caching
  flutter_rating_bar: ^4.0.0        # Rating stars
  provider: ^6.0.5                  # State management
  connectivity_plus: ^6.1.0         # Network connectivity detection

dev_dependencies:
  build_runner: ^2.4.11             # Code generation
  json_annotation: ^4.9.0           # JSON serialization
  json_serializable: ^6.8.0        # JSON serialization
```

---

## 🚀 How to Use

### 1. View All Products

```dart
import 'package:ecommerce_int2/screens/main/woocommerce_page.dart';

// Navigate to WooCommerce products page
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const WooCommercePage()),
);
```

### 2. Use the Product List Widget

```dart
import 'package:ecommerce_int2/widgets/woocommerce_product_list.dart';

// Display all products
WooCommerceProductList(featured: false)

// Display only featured products
WooCommerceProductList(featured: true)
```

### 3. Access Products Programmatically

#### Using ProductRepository (Recommended)

```dart
import 'package:ecommerce_int2/services/product_repository.dart';

final repository = ProductRepository();

// Get all products (with caching)
final products = await repository.getProducts();

// Force refresh from API
final freshProducts = await repository.getProducts(forceRefresh: true);

// Get featured products
final featured = await repository.getFeaturedProducts();

// Search products
final results = await repository.searchProducts('headphones');

// Get product by ID
final product = await repository.getProductById(123);

// Clear cache
await repository.clearCache();

// Test API connection
final isConnected = await repository.testConnection();
```

#### Using WooCommerceService Directly

```dart
import 'package:ecommerce_int2/services/woocommerce_service.dart';

final service = WooCommerceService();

// Fetch products with filters
final products = await service.fetchProducts(
  page: 1,
  perPage: 20,
  featured: true,
  category: 15,
  search: 'laptop',
);

// Fetch single product
final product = await service.fetchProductById(123);

// Test connection
final isConnected = await service.testConnection();
```

---

## 🔧 Configuration

### Change API Credentials

Edit `lib/config/woocommerce_config.dart`:

```dart
class WooCommerceConfig {
  static const String baseUrl = 'https://your-store.com';
  static const String consumerKey = 'your_consumer_key';
  static const String consumerSecret = 'your_consumer_secret';
}
```

Or update `lib/utils/app_config.dart`:

```dart
class AppConfig {
  static const String baseUrl = 'https://www.your-store.com/wp-json/wc/v3';
  static const String consumerKey = 'your_consumer_key';
  static const String consumerSecret = 'your_consumer_secret';
}
```

### Adjust Cache Settings

In `lib/config/woocommerce_config.dart`:

```dart
// Cache expiration time
static const Duration cacheExpiration = Duration(hours: 1);

// Maximum cached products
static const int maxCacheSize = 100;
```

In `lib/utils/app_config.dart`:

```dart
// Performance Settings
static const int maxCacheSize = 100;
static const Duration cacheExpiry = Duration(minutes: 5);
static const Duration networkTimeout = Duration(seconds: 30);
```

### Adjust Pagination

```dart
// Default products per page
static const int perPage = 20;

// Maximum page size
static const int maxPageSize = 100;
```

---

## 🧪 Testing

### Test API Connection

```dart
import 'package:ecommerce_int2/services/product_repository.dart';

final repository = ProductRepository();
final isConnected = await repository.testConnection();

if (isConnected) {
  print('✅ API connected successfully!');
} else {
  print('❌ API connection failed');
}
```

### View Cache Info

```dart
final repository = ProductRepository();
final cacheInfo = repository.getCacheInfo();

print('Cached products: ${cacheInfo['cachedProducts']}');
print('Last fetch: ${cacheInfo['lastFetchTime']}');
print('Cache valid: ${cacheInfo['isCacheValid']}');
```

### Test WooCommerce Service Directly

```dart
import 'package:ecommerce_int2/services/woocommerce_service.dart';

final service = WooCommerceService();
final isConnected = await service.testConnection();
```

---

## 📱 Running the App

### Install Dependencies

```bash
flutter pub get
```

### Generate Model Files (if needed)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Run the App

```bash
# For Android
flutter run

# For iOS
flutter run -d ios

# For specific device
flutter devices
flutter run -d <device-id>
```

### Build Release

```bash
# Android APK
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release

# iOS
flutter build ios --release
```

---

## 🎯 Best Practices Implemented

1. **Repository Pattern** – Clean separation of data layer with `ProductRepository`
2. **Service Layer Pattern** – Business logic separation with `WooCommerceService`
3. **Error Handling** – Comprehensive try-catch blocks with custom exceptions
4. **Caching Strategy** – Multi-layer caching (memory + persistent) with expiration
5. **Offline Support** – Graceful fallback to cached data when offline
6. **Loading States** – User-friendly loading indicators
7. **Code Documentation** – Detailed comments and documentation
8. **Type Safety** – Strong typing throughout
9. **Null Safety** – Flutter 3.0+ null safety
10. **Separation of Concerns** – Clean architecture with distinct layers
11. **Performance** – Image caching, lazy loading, pagination
12. **Retry Logic** – Exponential backoff for network requests
13. **Network Detection** – Connectivity monitoring for offline support

---

## 🔍 API Endpoints Used

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/wp-json/wc/v3/products` | GET | Fetch all products |
| `/wp-json/wc/v3/products?featured=true` | GET | Fetch featured products |
| `/wp-json/wc/v3/products/{id}` | GET | Fetch single product |
| `/wp-json/wc/v3/products?search=query` | GET | Search products |
| `/wp-json/wc/v3/products?category={id}` | GET | Filter by category |
| `/wp-json/wc/v3/products?page={n}&per_page={n}` | GET | Pagination |

---

## 📚 API Documentation

For complete WooCommerce REST API documentation:
- [WooCommerce REST API Docs](https://woocommerce.github.io/woocommerce-rest-api-docs/)
- [WooCommerce API Guide](https://woocommerce.com/document/woocommerce-rest-api/)

---

## 🐛 Troubleshooting

### Issue: Products not loading

1. Check internet connection
2. Verify API credentials in `woocommerce_config.dart` or `app_config.dart`
3. Check console logs for error messages
4. Test API connection: `await repository.testConnection()`
5. Verify base URL is correct: `https://tworksystem.com`
6. Check if WooCommerce REST API is enabled on the WordPress site

### Issue: Images not displaying

1. Ensure products have images in WooCommerce
2. Check image URLs are HTTPS
3. Clear app cache: `await repository.clearCache()`
4. Restart the app

### Issue: Cache not working

1. Check SharedPreferences permissions
2. Verify cache expiration settings
3. Clear cache manually: `await repository.clearCache()`
4. Check cache size limits

### Issue: Build errors

```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Issue: Authentication errors (401)

1. Verify Consumer Key and Secret are correct
2. Check if API keys have proper permissions (Read/Write)
3. Ensure base URL is correct
4. Check if WooCommerce REST API is enabled

---

## 👨‍💻 Developer Notes

### Code Generation

When you modify `woocommerce_product.dart` or other models with `@JsonSerializable`, regenerate the `.g.dart` files:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Adding New Fields

1. Add field to `WooCommerceProduct` model
2. Add `@JsonKey` annotation if needed
3. Run code generation: `dart run build_runner build --delete-conflicting-outputs`
4. Update UI to display new field

### Caching Strategy

The app uses a two-tier caching strategy:

1. **Memory Cache** – Fast access, cleared on app restart
2. **Persistent Cache** – SharedPreferences, survives app restarts

Cache expiration: 1 hour (configurable in `WooCommerceConfig`)

### Service Variants

The project includes multiple service implementations:

- `WooCommerceService` – Main service with full error handling
- `WooCommerceServiceCached` – Service with offline-first caching
- `WooCommerceServiceSimple` – Simplified service without model conflicts

Choose the appropriate service based on your needs.

---

## 📝 Project Information

- **Package Name:** `ecommerce_int2`
- **App Name:** T-Work Commerce
- **Package ID:** `com.twork.ecommerce`
- **Version:** 1.0.1
- **Flutter SDK:** >=3.0.0 <4.0.0
- **Dart SDK:** 3.0+

---

## 📝 License

This integration is part of the T-Work Commerce app.

---

## 🙏 Acknowledgments

- **TworkSystem** (tworksystem.com) – For providing the WooCommerce store
- **WooCommerce** – For the excellent REST API
- **Flutter Team** – For the amazing framework

---

## 📞 Support

For technical support or questions:
- Check the troubleshooting section above
- Review WooCommerce API documentation
- Inspect console logs for detailed error messages
- Check project README.md for general project information

---

**Built with ❤️ using Flutter & WooCommerce REST API**

**Last Updated:** January 27, 2025  
**Integration Version:** 1.0.1  
**WooCommerce API Version:** v3  
**Project:** T-Work Commerce (`ecommerce_int2`)
