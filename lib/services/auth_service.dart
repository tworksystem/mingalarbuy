import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api_service.dart';
import '../models/auth_response.dart';
import '../models/auth_user.dart';
import '../models/login_request.dart';
import '../models/register_request.dart';
import '../utils/app_config.dart';
import '../utils/network_utils.dart';
import 'auth_header_provider.dart';

class AuthService {
  static const String baseUrl = AppConfig.baseUrl;
  static const String wpBaseUrl = AppConfig.wpBaseUrl;
  static const String consumerKey = AppConfig.consumerKey;
  static const String consumerSecret = AppConfig.consumerSecret;

  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Busts reverse proxies / HTTP caches for `GET /users/me` (custom_fields / points).
  static Uri _usersMeUriNoCache() {
    return Uri.parse('$wpBaseUrl/users/me').replace(
      queryParameters: {
        '_t': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
  }

  // Storage keys
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String _rememberMeKey = 'remember_me';
  static const String _phoneKey = 'user_phone';

  /// Login user with email and password
  /// Uses ApiService.executeWithRetry for retry logic (3 attempts, 30s timeout)
  static Future<AuthResponse> login(LoginRequest request) async {
    try {
      final Uri uri = Uri.parse('$wpBaseUrl/users/me');
      final response = await ApiService.executeWithRetry(
        () => ApiService.post(
          uri.path,
          queryParameters:
              uri.queryParameters.isEmpty ? null : uri.queryParameters,
          skipAuth: true,
          headers: <String, dynamic>{
            'Content-Type': 'application/json',
            'Authorization':
                'Basic ${base64Encode(utf8.encode('${request.email}:${request.password}'))}',
          },
        ),
        timeout: AppConfig.networkTimeout,
        context: 'login',
      );

      if (response == null) {
        return AuthResponse.error(
          message: 'Request timeout or server unreachable. Please try again.',
        );
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic>? userData = ApiService.responseAsJsonMap(response);
        if (userData == null) {
          return AuthResponse.error(message: 'Login failed. Invalid response.');
        }
        print(
            'DEBUG: Login - Raw API response: ${userData['first_name']} ${userData['last_name']}, Meta: ${userData['meta']}');
        final user = AuthUser.fromJson(userData);
        print(
            'DEBUG: Login - Parsed user: ${user.firstName} ${user.lastName}, Phone: ${user.phone}');

        // Create authentication token
        final token =
            base64Encode(utf8.encode('${request.email}:${request.password}'));
        print('DEBUG: Created token for user: ${request.email}');

        // Store authentication data - always store token for persistent login
        // rememberMe defaults to true if not specified
        final shouldRemember = request.rememberMe;
        await _storeAuthData(user, shouldRemember, token: token);
        print(
            'DEBUG: Stored authentication data and token (rememberMe: $shouldRemember)');

        return AuthResponse.success(
          message: 'Login successful',
          user: user,
          token: token,
        );
      } else if (response.statusCode == 401) {
        return AuthResponse.error(
          message: 'Invalid email or password',
        );
      } else {
        return AuthResponse.error(
          message: 'Login failed. Please try again.',
        );
      }
    } catch (e) {
      print('Login error: $e');
      return AuthResponse.error(
        message: NetworkUtils.getErrorMessage(e),
      );
    }
  }

  /// Register new user
  static Future<AuthResponse> register(RegisterRequest request) async {
    try {
      // Validate request
      if (!request.isValid) {
        return AuthResponse.error(
          message: 'Please fill in all required fields correctly',
          errors: {'validation': request.validationErrors},
        );
      }

      // Create user via WooCommerce customers endpoint
      // Uses ApiService.executeWithRetry for retry logic (3 attempts, 30s timeout)
      final Uri regUri = Uri.parse('$baseUrl/customers');
      final response = await ApiService.executeWithRetry(
        () => ApiService.post(
          regUri.path,
          queryParameters:
              regUri.queryParameters.isEmpty ? null : regUri.queryParameters,
          skipAuth: true,
          headers: <String, dynamic>{
            'Content-Type': 'application/json',
            'Authorization':
                'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}',
          },
          data: <String, dynamic>{
            'email': request.email,
            'first_name': request.firstName,
            'last_name': request.lastName,
            'username': request.username ?? request.email.split('@')[0],
            'password': request.password,
            'billing': <String, dynamic>{
              'phone': request.phone,
            },
          },
        ),
        timeout: AppConfig.networkTimeout,
        context: 'register',
      );

      if (response == null) {
        return AuthResponse.error(
          message: 'Request timeout or server unreachable. Please try again.',
        );
      }

      print('Registration response status: ${response.statusCode}');
      print('Registration response body: ${ApiService.responseBodyString(response)}');

      if (response.statusCode == 201) {
        final Map<String, dynamic>? userData = ApiService.responseAsJsonMap(response);
        if (userData == null) {
          return AuthResponse.error(message: 'Registration failed. Invalid response.');
        }
        print(
            'DEBUG: Registration - Raw API response: ${userData['first_name']} ${userData['last_name']}, Billing: ${userData['billing']}');
        final user = AuthUser.fromJson(userData);
        print(
            'DEBUG: Registration - Parsed user: ${user.firstName} ${user.lastName}, Phone: ${user.phone}');

        // Store authentication data
        await _storeAuthData(user, false);

        return AuthResponse.success(
          message: 'Registration successful',
          user: user,
        );
      } else if (response.statusCode == 400) {
        final Map<String, dynamic>? errorData = ApiService.responseAsJsonMap(response) ??
            (json.decode(ApiService.responseBodyString(response))
                as Map<String, dynamic>?);
        if (errorData == null) {
          return AuthResponse.error(message: 'Registration failed');
        }
        String errorMessage = 'Registration failed';

        if (errorData['message'] != null) {
          errorMessage = errorData['message'];
        } else if (errorData['code'] != null) {
          switch (errorData['code']) {
            case 'woocommerce_rest_customer_invalid_email':
              errorMessage = 'Please enter a valid email address';
              break;
            case 'woocommerce_rest_customer_invalid_username':
              errorMessage =
                  'Username is already taken. Please choose another.';
              break;
            case 'woocommerce_rest_customer_invalid_password':
              errorMessage =
                  'Password is too weak. Please choose a stronger password.';
              break;
            default:
              errorMessage = errorData['message'] ?? 'Registration failed';
          }
        }

        return AuthResponse.error(
          message: errorMessage,
          errors: errorData,
        );
      } else {
        return AuthResponse.error(
          message: 'Registration failed. Please try again.',
        );
      }
    } catch (e) {
      print('Registration error: $e');
      return AuthResponse.error(
        message: NetworkUtils.getErrorMessage(e),
      );
    }
  }

  /// Get current user data
  /// Uses ApiService.executeWithRetry for retry logic (3 attempts, 30s timeout)
  static Future<AuthUser?> getCurrentUser() async {
    try {
      final token = await _secureStorage.read(key: _tokenKey);
      print('DEBUG: getCurrentUser - Token exists: ${token != null}');
      if (token == null) return null;

      final Uri meUri = _usersMeUriNoCache();
      final response = await ApiService.executeWithRetry(
        () => ApiService.get(
          meUri.path,
          queryParameters: meUri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
        ),
        timeout: AppConfig.networkTimeout,
        context: 'getCurrentUser',
      );

      if (response == null) {
        print('DEBUG: getCurrentUser - Request timeout or network failure');
        return null;
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic>? userData = ApiService.responseAsJsonMap(response);
        if (userData == null) {
          return null;
        }
        String? debugMetaPhone;
        final metaDyn = userData['meta'];
        if (metaDyn is Map<String, dynamic>) {
          debugMetaPhone = metaDyn['billing_phone'] as String?;
        } else if (metaDyn is List) {
          try {
            for (final item in metaDyn) {
              if (item is Map && item.containsKey('billing_phone')) {
                final val = item['billing_phone'];
                if (val is String) {
                  debugMetaPhone = val;
                  break;
                }
              }
            }
          } catch (_) {}
        }
        print(
            'DEBUG: getCurrentUser - Raw API response: ${userData['first_name']} ${userData['last_name']}, Phone(meta): $debugMetaPhone');
        var authUser = AuthUser.fromJson(userData);

        // Preserve critical identity fields from stored user if WP response is sparse
        try {
          final stored = await getStoredUser();
          if (stored != null) {
            final mergedEmail =
                (authUser.email.isNotEmpty) ? authUser.email : stored.email;
            final mergedFirst = (authUser.firstName.isNotEmpty)
                ? authUser.firstName
                : stored.firstName;
            final mergedLast = (authUser.lastName.isNotEmpty)
                ? authUser.lastName
                : stored.lastName;
            final mergedUsername = (authUser.username.isNotEmpty)
                ? authUser.username
                : stored.username;
            authUser = authUser.copyWith(
              email: mergedEmail,
              firstName: mergedFirst,
              lastName: mergedLast,
              username: mergedUsername,
            );
          }
        } catch (e) {
          print(
              'DEBUG: getCurrentUser - Failed to merge identity from storage: $e');
        }

        // Merge WooCommerce billing info (phone/address)
        try {
          Map<String, dynamic>? woo;
          if ((authUser.id) != 0) {
            woo = await _fetchWooCustomer(authUser.id);
          }
          if (woo == null && (authUser.email).isNotEmpty) {
            woo = await _findWooCustomerByEmail(authUser.email);
          }
          if (woo != null) {
            final wooBilling = (woo['billing'] as Map<String, dynamic>?) ?? {};
            final wooPhone = (wooBilling['phone'] as String?)?.trim();
            final billingAddress = _formatAddressFromWoo(wooBilling);
            final billingCity = (wooBilling['city'] as String?)?.trim();
            final billingCountry = (wooBilling['country'] as String?)?.trim();

            if ((wooPhone ?? '').isNotEmpty) {
              authUser = authUser.copyWith(phone: wooPhone);
            }
            if (billingAddress != null && billingAddress.isNotEmpty) {
              authUser = authUser.copyWith(billingAddress: billingAddress);
            }
            if ((billingCity ?? '').isNotEmpty) {
              authUser = authUser.copyWith(billingCity: billingCity);
            }
            if ((billingCountry ?? '').isNotEmpty) {
              authUser = authUser.copyWith(billingCountry: billingCountry);
            }
          }
        } catch (e) {
          print('DEBUG: getCurrentUser - Failed to merge Woo billing: $e');
        }

        // Fallback to locally stored phone if Woo/WordPress didn't provide
        final storedPhone = await _secureStorage.read(key: _phoneKey);
        print(
            'DEBUG: getCurrentUser - Retrieved phone from storage: $storedPhone');
        if ((authUser.phone ?? '').isEmpty && storedPhone != null) {
          authUser = authUser.copyWith(phone: storedPhone);
          print(
              'DEBUG: getCurrentUser - Applied stored phone: ${authUser.phone}');
        }

        // Persist merged phone locally so UI can always read it
        if ((authUser.phone ?? '').isNotEmpty) {
          await _secureStorage.write(key: _phoneKey, value: authUser.phone!);
        }

        print(
            'DEBUG: getCurrentUser - Parsed user: ${authUser.firstName} ${authUser.lastName}, Phone: ${authUser.phone}');
        return authUser;
      } else {
        print(
            'DEBUG: getCurrentUser - API call failed with status: ${response.statusCode}');
        print(
            'DEBUG: getCurrentUser - Response body: ${ApiService.responseBodyString(response)}');
        // Don't automatically logout - let the caller decide
        return null;
      }
    } catch (e) {
      print('Get current user error: $e');
      return null;
    }
  }

  /// Fetch WooCommerce customer by id using consumer credentials
  static Future<Map<String, dynamic>?> _fetchWooCustomer(int customerId) async {
    final uri = Uri.parse('$baseUrl/customers/$customerId');
    final Map<String, dynamic> headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}',
    };
    final resp = await ApiService.executeWithRetry(
      () => ApiService.get(
        uri.path,
        queryParameters:
            uri.queryParameters.isEmpty ? null : uri.queryParameters,
        skipAuth: true,
        headers: headers,
      ),
      timeout: AppConfig.networkTimeout,
      context: '_fetchWooCustomer',
    );
    if (resp != null && resp.statusCode == 200) {
      return ApiService.responseAsJsonMap(resp);
    }
    print(
        'DEBUG: _fetchWooCustomer - status=${resp?.statusCode} body=${ApiService.responseBodyString(resp)}');
    return null;
  }

  /// Fallback: find Woo customer by email
  static Future<Map<String, dynamic>?> _findWooCustomerByEmail(
      String email) async {
    final uri = Uri.parse(
        '$baseUrl/customers?email=${Uri.encodeQueryComponent(email)}');
    final Map<String, dynamic> headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}',
    };
    final resp = await ApiService.executeWithRetry(
      () => ApiService.get(
        uri.path,
        queryParameters: uri.queryParameters,
        skipAuth: true,
        headers: headers,
      ),
      timeout: AppConfig.networkTimeout,
      context: '_findWooCustomerByEmail',
    );
    if (resp != null && resp.statusCode == 200) {
      final Object? data = resp.data;
      if (data is List && data.isNotEmpty) {
        final Object? first = data.first;
        if (first is Map) {
          return Map<String, dynamic>.from(first);
        }
      }
      if (data is String) {
        final Object? decoded = json.decode(data);
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
          return Map<String, dynamic>.from(decoded.first as Map);
        }
      }
    }
    print(
        'DEBUG: _findWooCustomerByEmail - status=${resp?.statusCode} body=${ApiService.responseBodyString(resp)}');
    return null;
  }

  /// Format a readable address string from Woo billing map
  static String? _formatAddressFromWoo(Map<String, dynamic> billing) {
    final parts = <String>[];
    void add(String? v) {
      if (v != null && v.toString().trim().isNotEmpty) {
        parts.add(v.toString().trim());
      }
    }

    add(billing['address_1']);
    add(billing['address_2']);
    add(billing['city']);
    add(billing['postcode']);
    add(billing['country']);
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Update user profile
  static Future<AuthResponse> updateProfile(AuthUser user) async {
    try {
      final token = await _secureStorage.read(key: _tokenKey);
      print(
          'DEBUG: Retrieved token from storage: ${token != null ? "Token exists" : "No token found"}');
      if (token == null) {
        print('DEBUG: No authentication token found in storage');
        return AuthResponse.error(message: 'Not authenticated');
      }

      // 1) Update core profile via WordPress user profile endpoint (names)
      final updateData = {
        'first_name': user.firstName,
        'last_name': user.lastName,
        'meta': {
          'billing_phone': user.phone,
        },
      };
      print('DEBUG: updateProfile - Sending update data: $updateData');

      final Uri meUri = Uri.parse('$wpBaseUrl/users/me');
      final response = await ApiService.executeWithRetry(
        () => ApiService.post(
          meUri.path,
          queryParameters:
              meUri.queryParameters.isEmpty ? null : meUri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
          data: updateData,
        ),
        timeout: AppConfig.networkTimeout,
        context: 'updateProfile',
      );

      if (response == null) {
        return AuthResponse.error(
          message: 'Request timeout or server unreachable. Please try again.',
        );
      }

      print('Update profile response status: ${response.statusCode}');
      print(
          'Update profile response body: ${ApiService.responseBodyString(response)}');

      if (response.statusCode == 200) {
        final Map<String, dynamic>? userData = ApiService.responseAsJsonMap(response);
        if (userData == null) {
          return AuthResponse.error(message: 'Invalid profile response');
        }
        var updatedUser = AuthUser.fromJson(userData);

        // 2) Persist phone (and names) to WooCommerce customer as well
        // WordPress users/me may ignore arbitrary meta; WooCommerce owns billing.
        try {
          if (updatedUser.id != 0) {
            print(
                'DEBUG: updateProfile - Updating WooCommerce customer ${updatedUser.id}');
            await _updateWooCustomer(
              customerId: updatedUser.id,
              firstName: user.firstName,
              lastName: user.lastName,
              phone: user.phone,
            );
          } else {
            print(
                'DEBUG: updateProfile - Skipping WooCommerce update due to missing user id');
          }
        } catch (e) {
          // Don't fail the whole flow if Woo update fails; log it
          print(
              'DEBUG: updateProfile - WooCommerce customer update failed: $e');
        }

        // Preserve the phone number that was just updated locally
        print('DEBUG: updateProfile - Preserving phone number: ${user.phone}');
        updatedUser = updatedUser.copyWith(phone: user.phone);
        print(
            'DEBUG: updateProfile - Updated user phone: ${updatedUser.phone}');

        // Update stored user data
        await _storeUserData(updatedUser);

        return AuthResponse.success(
          message: 'Profile updated successfully',
          user: updatedUser,
        );
      } else {
        final Map<String, dynamic>? errorData = ApiService.responseAsJsonMap(response);
        if (errorData == null) {
          return AuthResponse.error(message: 'Failed to update profile');
        }
        String errorMessage = 'Failed to update profile';

        if (errorData['message'] != null) {
          errorMessage = errorData['message'].toString();
        } else if (errorData['code'] != null) {
          switch (errorData['code']) {
            case 'rest_user_invalid_id':
              errorMessage = 'User not found';
              break;
            case 'rest_user_invalid_data':
              errorMessage = 'Invalid profile data provided';
              break;
            case 'rest_cannot_edit':
              errorMessage = 'You are not allowed to edit this profile';
              break;
            default:
              errorMessage = errorData['message'] ?? 'Failed to update profile';
          }
        }

        return AuthResponse.error(message: errorMessage);
      }
    } catch (e) {
      print('Update profile error: $e');
      return AuthResponse.error(
        message: NetworkUtils.getErrorMessage(e),
      );
    }
  }

  /// Update WooCommerce customer (billing) using app consumer credentials
  static Future<void> _updateWooCustomer({
    required int customerId,
    String? firstName,
    String? lastName,
    String? phone,
    Map<String, dynamic>? billingExtra,
  }) async {
    final uri = Uri.parse('$baseUrl/customers/$customerId');
    final Map<String, dynamic> headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}',
    };
    final body = <String, dynamic>{
      if ((firstName ?? '').isNotEmpty) 'first_name': firstName,
      if ((lastName ?? '').isNotEmpty) 'last_name': lastName,
      'billing': {
        if ((firstName ?? '').isNotEmpty) 'first_name': firstName,
        if ((lastName ?? '').isNotEmpty) 'last_name': lastName,
        if ((phone ?? '').isNotEmpty) 'phone': phone,
        ...?billingExtra,
      }
    };

    print('DEBUG: _updateWooCustomer - PUT $uri body=$body');
    final resp = await ApiService.executeWithRetry(
      () => ApiService.put(
        uri.path,
        queryParameters:
            uri.queryParameters.isEmpty ? null : uri.queryParameters,
        skipAuth: true,
        headers: headers,
        data: body,
      ),
      timeout: AppConfig.networkTimeout,
      context: '_updateWooCustomer',
    );
    print(
        'DEBUG: _updateWooCustomer - status=${resp?.statusCode} body=${ApiService.responseBodyString(resp)}');

    if (resp == null || resp.statusCode != 200) {
      String msg;
      if (resp == null) {
        msg = 'Request timeout - Woo update failed';
      } else {
        try {
          final Map<String, dynamic>? data = ApiService.responseAsJsonMap(resp);
          msg = data?['message']?.toString() ?? ApiService.responseBodyString(resp);
        } catch (_) {
          msg = 'Status ${resp.statusCode}';
        }
        msg = 'Woo update failed: $msg';
      }
      throw Exception(msg);
    }
  }

  /// Public helper to update WooCommerce billing for the current user
  static Future<AuthResponse> updateBillingForCurrentUser({
    String? firstName,
    String? lastName,
    String? phone,
    Map<String, dynamic>? billingExtra,
  }) async {
    try {
      final stored = await getStoredUser();
      if (stored == null || stored.id == 0) {
        return AuthResponse.error(message: 'Not authenticated');
      }

      await _updateWooCustomer(
        customerId: stored.id,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        billingExtra: billingExtra,
      );

      // Refresh local store with new phone if provided
      var updated = stored;
      if ((phone ?? '').isNotEmpty) {
        updated = updated.copyWith(phone: phone);
        await _storeUserData(updated);
      }
      return AuthResponse.success(message: 'Billing updated', user: updated);
    } catch (e) {
      return AuthResponse.error(message: 'Failed to update billing: $e');
    }
  }

  /// Change password
  static Future<AuthResponse> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final token = await _secureStorage.read(key: _tokenKey);
      if (token == null) {
        return AuthResponse.error(message: 'Not authenticated');
      }

      // Get current user to get user email
      final currentUser = await getCurrentUser();
      if (currentUser == null) {
        return AuthResponse.error(message: 'User not found');
      }

      // First verify current password by trying to authenticate
      final Uri meUri = _usersMeUriNoCache();
      final verifyResponse = await ApiService.executeWithRetry(
        () => ApiService.get(
          meUri.path,
          queryParameters: meUri.queryParameters,
          skipAuth: true,
          headers: <String, dynamic>{
            'Content-Type': 'application/json',
            'Authorization':
                'Basic ${base64Encode(utf8.encode('${currentUser.email}:$currentPassword'))}',
          },
        ),
        timeout: AppConfig.networkTimeout,
        context: 'changePassword_verify',
      );

      if (verifyResponse == null || verifyResponse.statusCode != 200) {
        return AuthResponse.error(
          message: 'Current password is incorrect',
        );
      }

      // Update password via WordPress user endpoint
      final Uri meUriPost = Uri.parse('$wpBaseUrl/users/me');
      final response = await ApiService.executeWithRetry(
        () => ApiService.post(
          meUriPost.path,
          queryParameters: meUriPost.queryParameters.isEmpty
              ? null
              : meUriPost.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
          data: <String, dynamic>{
            'password': newPassword,
          },
        ),
        timeout: AppConfig.networkTimeout,
        context: 'changePassword',
      );

      if (response == null) {
        return AuthResponse.error(
          message: 'Request timeout or server unreachable. Please try again.',
        );
      }

      print('Change password response status: ${response.statusCode}');
      print(
          'Change password response body: ${ApiService.responseBodyString(response)}');

      if (response.statusCode == 200) {
        // Update stored token with new password
        final newToken =
            base64Encode(utf8.encode('${currentUser.email}:$newPassword'));
        await _secureStorage.write(key: _tokenKey, value: newToken);

        return AuthResponse.success(
          message: 'Password changed successfully',
        );
      } else {
        final Map<String, dynamic>? errorData = ApiService.responseAsJsonMap(response);
        if (errorData == null) {
          return AuthResponse.error(message: 'Failed to change password');
        }
        String errorMessage = 'Failed to change password';

        if (errorData['message'] != null) {
          errorMessage = errorData['message'].toString();
        } else if (errorData['code'] != null) {
          switch (errorData['code']) {
            case 'rest_user_invalid_password':
              errorMessage =
                  'New password is too weak. Please choose a stronger password.';
              break;
            case 'rest_user_invalid_id':
              errorMessage = 'User not found';
              break;
            case 'rest_cannot_edit':
              errorMessage = 'You are not allowed to change this password';
              break;
            default:
              errorMessage =
                  errorData['message'] ?? 'Failed to change password';
          }
        }

        return AuthResponse.error(message: errorMessage);
      }
    } catch (e) {
      print('Change password error: $e');
      return AuthResponse.error(
        message: NetworkUtils.getErrorMessage(e),
      );
    }
  }

  /// Logout user
  static Future<void> logout() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _userKey);
    await _secureStorage.delete(key: _rememberMeKey);
    await _secureStorage.delete(key: _phoneKey);
  }

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await _secureStorage.read(key: _tokenKey);
    return token != null;
  }

  /// Get stored authentication token
  static Future<String?> getStoredToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  /// Headers for REST calls: [Authorization] when a token exists.
  static Future<Map<String, String>> getAuthorizationHeaders() async {
    return AuthHeaderProvider.buildHeaders();
  }

  /// Get stored user data
  static Future<AuthUser?> getStoredUser() async {
    try {
      final userJson = await _secureStorage.read(key: _userKey);
      if (userJson != null) {
        final userData = json.decode(userJson);
        print('DEBUG: getStoredUser - Raw stored user data: $userData');
        var authUser = AuthUser.fromJson(userData);
        print(
            'DEBUG: getStoredUser - Parsed user from JSON: ${authUser.firstName} ${authUser.lastName}, Phone: ${authUser.phone}');

        // Merge Woo billing to ensure phone/city/address appear even offline
        try {
          if (authUser.id != 0) {
            final woo = await _fetchWooCustomer(authUser.id);
            final billing = (woo?['billing'] as Map<String, dynamic>?) ?? {};
            final wooPhone = (billing['phone'] as String?)?.trim();
            final wooCity = (billing['city'] as String?)?.trim();
            final formatted = _formatAddressFromWoo(billing);
            if ((wooPhone ?? '').isNotEmpty) {
              authUser = authUser.copyWith(phone: wooPhone);
              // Persist merged phone for subsequent reads
              await _secureStorage.write(key: _phoneKey, value: wooPhone);
            }
            if ((wooCity ?? '').isNotEmpty) {
              authUser = authUser.copyWith(billingCity: wooCity);
            }
            if (formatted != null && formatted.isNotEmpty) {
              authUser = authUser.copyWith(billingAddress: formatted);
            }
          }
        } catch (e) {
          print('DEBUG: getStoredUser - Woo merge failed: $e');
        }

        return authUser;
      }
      return null;
    } catch (e) {
      print('Get stored user error: $e');
      return null;
    }
  }

  /// Store authentication data
  /// Always stores token for persistent login (rememberMe is respected but token is always saved)
  static Future<void> _storeAuthData(AuthUser user, bool rememberMe,
      {String? token}) async {
    await _storeUserData(user);

    // Always store rememberMe preference (defaults to true for persistent login)
    await _secureStorage.write(
        key: _rememberMeKey, value: rememberMe.toString());

    // Always store the authentication token for persistent login
    // This ensures users stay logged in even if rememberMe is false
    // The rememberMe flag is used for UI purposes only
    if (token != null) {
      await _secureStorage.write(key: _tokenKey, value: token);
      print('DEBUG: _storeAuthData - Token stored for persistent login');
    } else {
      print('DEBUG: _storeAuthData - Warning: No token provided for storage');
    }
  }

  /// Store user data
  static Future<void> _storeUserData(AuthUser user) async {
    print(
        'DEBUG: _storeUserData - Storing user: ${user.firstName} ${user.lastName}, Phone: ${user.phone}');
    final userJson = user.toJson();
    print('DEBUG: _storeUserData - User JSON: $userJson');
    await _secureStorage.write(key: _userKey, value: json.encode(userJson));

    // Store phone number separately since WordPress doesn't return meta fields
    if (user.phone != null && user.phone!.isNotEmpty) {
      print('DEBUG: _storeUserData - Storing phone number: ${user.phone}');
      await _secureStorage.write(key: _phoneKey, value: user.phone!);
    } else {
      print(
          'DEBUG: _storeUserData - No phone number to store, clearing storage');
      await _secureStorage.delete(key: _phoneKey);
    }
  }

  /// Test phone number storage and retrieval
  static Future<void> testPhoneStorage() async {
    print('DEBUG: testPhoneStorage - Starting phone storage test');

    // Create a test user with phone number
    final testUser = AuthUser(
      id: 999,
      email: 'test@example.com',
      firstName: 'Test',
      lastName: 'User',
      username: 'testuser',
      phone: '+1234567890',
    );

    print(
        'DEBUG: testPhoneStorage - Created test user: ${testUser.firstName} ${testUser.lastName}, Phone: ${testUser.phone}');

    // Store the test user
    await _storeUserData(testUser);
    print('DEBUG: testPhoneStorage - Stored test user');

    // Retrieve the test user
    final retrievedUser = await getStoredUser();
    print(
        'DEBUG: testPhoneStorage - Retrieved user: ${retrievedUser?.firstName} ${retrievedUser?.lastName}, Phone: ${retrievedUser?.phone}');

    // Clean up
    await _secureStorage.delete(key: _userKey);
    await _secureStorage.delete(key: _phoneKey);
    print('DEBUG: testPhoneStorage - Cleaned up test data');
  }

  /// Forgot password
  static Future<AuthResponse> forgotPassword(String email) async {
    try {
      final Uri lostUri = Uri.parse('$wpBaseUrl/users/lost-password');
      final response = await ApiService.executeWithRetry(
        () => ApiService.post(
          lostUri.path,
          queryParameters:
              lostUri.queryParameters.isEmpty ? null : lostUri.queryParameters,
          skipAuth: true,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
          data: <String, dynamic>{
            'user_login': email,
          },
        ),
        timeout: AppConfig.networkTimeout,
        context: 'forgotPassword',
      );

      if (response == null) {
        return AuthResponse.error(
          message: 'Request timeout or server unreachable. Please try again.',
        );
      }

      if (response.statusCode == 200) {
        return AuthResponse.success(
          message: 'Password reset email sent. Please check your inbox.',
        );
      } else {
        return AuthResponse.error(
          message: 'Failed to send reset email. Please try again.',
        );
      }
    } catch (e) {
      print('Forgot password error: $e');
      return AuthResponse.error(
        message: NetworkUtils.getErrorMessage(e),
      );
    }
  }
}
