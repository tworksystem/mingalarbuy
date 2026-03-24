import 'package:ecommerce_int2/services/woocommerce_service.dart';
import 'package:ecommerce_int2/services/woocommerce_service_cached.dart';
import 'package:ecommerce_int2/services/connectivity_service.dart';

Future<void> debugWooCommerceAPI() async {
  print('=== WooCommerce API Debug ===\n');

  // Test 1: Check connectivity
  print('1. Testing connectivity...');
  final connectivityService = ConnectivityService();
  await connectivityService.initialize();
  final hasConnection = await connectivityService.checkInternetConnectivity();
  print('   Connection status: ${hasConnection ? "✅ Online" : "❌ Offline"}');
  print(
      '   Connection type: ${connectivityService.connectionType}\n');

  if (!hasConnection) {
    print('❌ No internet connection. Cannot test API.\n');
    return;
  }

  // Test 2: Check basic API connection
  print('2. Testing basic API connection...');
  try {
    final service = WooCommerceService();
    final connection = await service.checkConnection();
    print('   API connection: ${connection ? "✅ Success" : "❌ Failed"}\n');
  } catch (e) {
    print('   API connection error: $e\n');
    return;
  }

  // Test 3: Fetch products and check image URLs
  print('3. Testing product fetch and image URLs...');
  try {
    final service = WooCommerceService();
    final products = await service.getProducts(perPage: 5);
    print('   Fetched ${products.length} products\n');

    for (int i = 0; i < products.length; i++) {
      final product = products[i];
      print('   Product ${i + 1}:');
      print('     - ID: ${product.id}');
      print('     - Name: ${product.name}');
      print('     - Price: \$${product.price}');
      print('     - Images count: ${product.images.length}');

      if (product.images.isNotEmpty) {
        print('     - First image URL: ${product.images.first.src}');
        print('     - Image valid: ${product.images.first.src.isNotEmpty}');

        // Test if URL is accessible
        if (product.images.first.src.isNotEmpty) {
          try {
            final uri = Uri.parse(product.images.first.src);
            print(
                '     - URL parsed successfully: ${uri.scheme}://${uri.host}');
            print('     - URL path: ${uri.path}');
          } catch (e) {
            print('     - URL parse error: $e');
          }
        }
      } else {
        print('     - ❌ No images found for this product');
      }
      print('');
    }
  } catch (e) {
    print('   Product fetch error: $e\n');
  }

  // Test 4: Test cached service
  print('4. Testing cached service...');
  try {
    final cachedProducts =
        await WooCommerceServiceCached.getProducts(perPage: 3);
    print('   Cached service: ✅ Success');
    print('   Products from cache: ${cachedProducts.length}');

    if (cachedProducts.isNotEmpty) {
      final firstProduct = cachedProducts.first;
      print('   First cached product images: ${firstProduct.images.length}');
      if (firstProduct.images.isNotEmpty) {
        print('   First cached image URL: ${firstProduct.images.first.src}');
      }
    }
  } catch (e) {
    print('   Cached service error: $e');
  }

  // Test 5: Test featured products
  print('\n5. Testing featured products...');
  try {
    final service = WooCommerceService();
    final featured = await service.getFeaturedProducts(perPage: 3);
    print('   Featured products: ${featured.length}');

    for (var product in featured) {
      print('   - ${product.name}: ${product.images.length} images');
      if (product.images.isNotEmpty) {
        print('     Image: ${product.images.first.src}');
      }
    }
  } catch (e) {
    print('   Featured products error: $e');
  }

  print('\n=== Debug Complete ===');
}

/// Test specific image URL
Future<void> testImageUrl(String imageUrl) async {
  print('Testing image URL: $imageUrl');

  try {
    final uri = Uri.parse(imageUrl);
    print('✅ URL parsed successfully');
    print('   Scheme: ${uri.scheme}');
    print('   Host: ${uri.host}');
    print('   Path: ${uri.path}');
    print('   Query: ${uri.query}');

    // Check if it's HTTPS
    if (uri.scheme == 'https') {
      print('✅ HTTPS URL (secure)');
    } else {
      print('⚠️ Non-HTTPS URL: ${uri.scheme}');
    }

    // Check if host is accessible
    if (uri.host.isNotEmpty) {
      print('✅ Host specified: ${uri.host}');
    } else {
      print('❌ No host specified');
    }
  } catch (e) {
    print('❌ URL parse error: $e');
  }
}
