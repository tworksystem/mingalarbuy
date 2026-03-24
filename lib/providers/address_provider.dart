import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/address.dart';

class AddressProvider with ChangeNotifier {
  List<Address> _addresses = [];
  bool _isLoading = false;
  String? _errorMessage;
  static const String _addressesKey = 'user_addresses';

  // Getters
  List<Address> get addresses => List.unmodifiable(_addresses);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasAddresses => _addresses.isNotEmpty;

  // Get default address
  Address? get defaultAddress {
    try {
      return _addresses.firstWhere((address) => address.isDefault);
    } catch (e) {
      return _addresses.isNotEmpty ? _addresses.first : null;
    }
  }

  // Get addresses by type
  List<Address> getAddressesByType(AddressType type) {
    return _addresses.where((address) => address.type == type).toList();
  }

  // Get home addresses
  List<Address> get homeAddresses => getAddressesByType(AddressType.home);

  // Get work addresses
  List<Address> get workAddresses => getAddressesByType(AddressType.work);

  // Get other addresses
  List<Address> get otherAddresses => getAddressesByType(AddressType.other);

  AddressProvider() {
    _loadAddressesFromStorage();
  }

  /// Load addresses from SharedPreferences
  Future<void> _loadAddressesFromStorage() async {
    _setLoading(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final addressesJson = prefs.getString(_addressesKey);

      if (addressesJson != null) {
        final List<dynamic> addressesData = json.decode(addressesJson);
        _addresses = addressesData
            .map((address) => Address.fromJson(address as Map<String, dynamic>))
            .toList();
        print(
            'DEBUG: Addresses loaded from storage - ${_addresses.length} addresses');
      }
    } catch (e) {
      print('Error loading addresses from storage: $e');
      _setError('Failed to load addresses');
    } finally {
      _setLoading(false);
    }
  }

  /// Save addresses to SharedPreferences
  Future<void> _saveAddressesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final addressesJson =
          json.encode(_addresses.map((address) => address.toJson()).toList());
      await prefs.setString(_addressesKey, addressesJson);
      print(
          'DEBUG: Addresses saved to storage - ${_addresses.length} addresses');
    } catch (e) {
      print('Error saving addresses to storage: $e');
    }
  }

  /// Add new address
  Future<Address?> addAddress({
    required String userId,
    required String firstName,
    required String lastName,
    required String addressLine1,
    required String city,
    required String state,
    required String postalCode,
    required String country,
    required String phone,
    String company = '',
    String addressLine2 = '',
    String email = '',
    AddressType type = AddressType.home,
    bool isDefault = false,
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // If this is set as default, unset other defaults
      if (isDefault) {
        for (int i = 0; i < _addresses.length; i++) {
          if (_addresses[i].isDefault) {
            _addresses[i] = _addresses[i].copyWith(isDefault: false);
          }
        }
      }

      // Generate address ID
      final addressId = 'ADDR-${DateTime.now().millisecondsSinceEpoch}';

      // Create address
      final address = Address(
        id: addressId,
        userId: userId,
        firstName: firstName,
        lastName: lastName,
        company: company,
        addressLine1: addressLine1,
        addressLine2: addressLine2,
        city: city,
        state: state,
        postalCode: postalCode,
        country: country,
        phone: phone,
        email: email,
        type: type,
        isDefault: isDefault,
        createdAt: DateTime.now(),
        notes: notes,
        metadata: metadata,
      );

      // Validate address
      if (!address.isValid) {
        _setError('Invalid address: ${address.validationErrors.join(', ')}');
        return null;
      }

      // Add to addresses list
      _addresses.add(address);
      await _saveAddressesToStorage();
      notifyListeners();

      print('DEBUG: Address added - $addressId');
      return address;
    } catch (e) {
      print('Error adding address: $e');
      _setError('Failed to add address: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Update existing address
  Future<Address?> updateAddress({
    required String addressId,
    String? firstName,
    String? lastName,
    String? company,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    String? phone,
    String? email,
    AddressType? type,
    bool? isDefault,
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final addressIndex =
          _addresses.indexWhere((address) => address.id == addressId);
      if (addressIndex == -1) {
        _setError('Address not found');
        return null;
      }

      final existingAddress = _addresses[addressIndex];

      // If setting as default, unset other defaults
      if (isDefault == true) {
        for (int i = 0; i < _addresses.length; i++) {
          if (i != addressIndex && _addresses[i].isDefault) {
            _addresses[i] = _addresses[i].copyWith(isDefault: false);
          }
        }
      }

      // Update address
      final updatedAddress = existingAddress.copyWith(
        firstName: firstName ?? existingAddress.firstName,
        lastName: lastName ?? existingAddress.lastName,
        company: company ?? existingAddress.company,
        addressLine1: addressLine1 ?? existingAddress.addressLine1,
        addressLine2: addressLine2 ?? existingAddress.addressLine2,
        city: city ?? existingAddress.city,
        state: state ?? existingAddress.state,
        postalCode: postalCode ?? existingAddress.postalCode,
        country: country ?? existingAddress.country,
        phone: phone ?? existingAddress.phone,
        email: email ?? existingAddress.email,
        type: type ?? existingAddress.type,
        isDefault: isDefault ?? existingAddress.isDefault,
        updatedAt: DateTime.now(),
        notes: notes ?? existingAddress.notes,
        metadata: metadata ?? existingAddress.metadata,
      );

      // Validate updated address
      if (!updatedAddress.isValid) {
        _setError(
            'Invalid address: ${updatedAddress.validationErrors.join(', ')}');
        return null;
      }

      _addresses[addressIndex] = updatedAddress;
      await _saveAddressesToStorage();
      notifyListeners();

      print('DEBUG: Address updated - $addressId');
      return updatedAddress;
    } catch (e) {
      print('Error updating address: $e');
      _setError('Failed to update address: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Delete address
  Future<bool> deleteAddress(String addressId) async {
    _setLoading(true);
    _clearError();

    try {
      final addressIndex =
          _addresses.indexWhere((address) => address.id == addressId);
      if (addressIndex == -1) {
        _setError('Address not found');
        return false;
      }

      _addresses.removeAt(addressIndex);
      await _saveAddressesToStorage();
      notifyListeners();

      print('DEBUG: Address deleted - $addressId');
      return true;
    } catch (e) {
      print('Error deleting address: $e');
      _setError('Failed to delete address');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Set default address
  Future<bool> setDefaultAddress(String addressId) async {
    _setLoading(true);
    _clearError();

    try {
      final addressIndex =
          _addresses.indexWhere((address) => address.id == addressId);
      if (addressIndex == -1) {
        _setError('Address not found');
        return false;
      }

      // Unset current default
      for (int i = 0; i < _addresses.length; i++) {
        if (_addresses[i].isDefault) {
          _addresses[i] = _addresses[i].copyWith(isDefault: false);
        }
      }

      // Set new default
      _addresses[addressIndex] = _addresses[addressIndex].copyWith(
        isDefault: true,
        updatedAt: DateTime.now(),
      );

      await _saveAddressesToStorage();
      notifyListeners();

      print('DEBUG: Default address set - $addressId');
      return true;
    } catch (e) {
      print('Error setting default address: $e');
      _setError('Failed to set default address');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Get address by ID
  Address? getAddressById(String addressId) {
    try {
      return _addresses.firstWhere((address) => address.id == addressId);
    } catch (e) {
      return null;
    }
  }

  /// Search addresses
  List<Address> searchAddresses(String query) {
    if (query.isEmpty) return _addresses;

    final lowercaseQuery = query.toLowerCase();
    return _addresses.where((address) {
      return address.firstName.toLowerCase().contains(lowercaseQuery) ||
          address.lastName.toLowerCase().contains(lowercaseQuery) ||
          address.city.toLowerCase().contains(lowercaseQuery) ||
          address.state.toLowerCase().contains(lowercaseQuery) ||
          address.country.toLowerCase().contains(lowercaseQuery) ||
          address.phone.contains(query);
    }).toList();
  }

  /// Clear all addresses (for testing)
  Future<void> clearAllAddresses() async {
    _setLoading(true);
    try {
      _addresses.clear();
      await _saveAddressesToStorage();
      notifyListeners();
      print('DEBUG: All addresses cleared');
    } catch (e) {
      print('Error clearing addresses: $e');
      _setError('Failed to clear addresses');
    } finally {
      _setLoading(false);
    }
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error message
  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Clear error message
  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Force refresh addresses from storage
  Future<void> refreshAddresses() async {
    await _loadAddressesFromStorage();
  }
}
