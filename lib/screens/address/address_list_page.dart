import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/providers/address_provider.dart';
import 'package:ecommerce_int2/models/address.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'add_edit_address_page.dart';

class AddressListPage extends StatefulWidget {
  const AddressListPage({super.key});

  @override
  _AddressListPageState createState() => _AddressListPageState();
}

class _AddressListPageState extends State<AddressListPage> {
  String _searchQuery = '';
  AddressType? _selectedType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        iconTheme: IconThemeData(color: darkGrey),
        title: Text(
          'My Addresses',
          style: TextStyle(
            color: darkGrey,
            fontWeight: FontWeight.w500,
            fontSize: 18.0,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Consumer<AddressProvider>(
        builder: (context, addressProvider, child) {
          if (addressProvider.isLoading) {
            return Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
              ),
            );
          }

          if (!addressProvider.hasAddresses) {
            return _buildEmptyState();
          }

          List<Address> addresses = addressProvider.addresses;

          // Apply search filter
          if (_searchQuery.isNotEmpty) {
            addresses = addressProvider.searchAddresses(_searchQuery);
          }

          // Apply type filter
          if (_selectedType != null) {
            addresses = addresses
                .where((address) => address.type == _selectedType)
                .toList();
          }

          if (addresses.isEmpty) {
            return _buildNoResultsState();
          }

          return AppPullToRefresh(
            onRefresh: () async {
              // Addresses are stored locally; reload view state.
              // (Future: if remote sync is added, call it here.)
              if (!mounted) return;
              setState(() {});
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(16),
              itemCount: addresses.length,
              itemBuilder: (context, index) {
                final address = addresses[index];
                return _buildAddressCard(address);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddAddress,
        backgroundColor: mediumYellow,
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off,
            size: 100,
            color: Colors.grey,
          ),
          SizedBox(height: 20),
          Text(
            'No addresses yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: darkGrey,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Add your first address to get started',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 30),
          ElevatedButton(
            onPressed: _navigateToAddAddress,
            style: ElevatedButton.styleFrom(
              backgroundColor: mediumYellow,
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            child: Text(
              'Add Address',
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

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'No addresses found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Try adjusting your search or filter',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(Address address) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _navigateToEditAddress(address),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getAddressTypeIcon(address.type),
                        color: mediumYellow,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        address.typeText,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: darkGrey,
                        ),
                      ),
                      if (address.isDefault) ...[
                        SizedBox(width: 8),
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Default',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  PopupMenuButton(
                    onSelected: (value) => _handleMenuAction(value, address),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 16),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      if (!address.isDefault)
                        PopupMenuItem(
                          value: 'set_default',
                          child: Row(
                            children: [
                              Icon(Icons.star, size: 16),
                              SizedBox(width: 8),
                              Text('Set as Default'),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 16, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                address.fullName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: darkGrey,
                ),
              ),
              SizedBox(height: 4),
              Text(
                address.formattedAddress,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              if (address.phone.isNotEmpty) ...[
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.phone,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    SizedBox(width: 4),
                    Text(
                      address.phone,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _getAddressTypeIcon(AddressType type) {
    switch (type) {
      case AddressType.home:
        return Icons.home;
      case AddressType.work:
        return Icons.work;
      case AddressType.other:
        return Icons.location_on;
    }
  }

  void _navigateToAddAddress() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEditAddressPage(),
      ),
    );
  }

  void _navigateToEditAddress(Address address) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEditAddressPage(address: address),
      ),
    );
  }

  void _handleMenuAction(String action, Address address) {
    final addressProvider =
        Provider.of<AddressProvider>(context, listen: false);

    switch (action) {
      case 'edit':
        _navigateToEditAddress(address);
        break;
      case 'set_default':
        addressProvider.setDefaultAddress(address.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Default address updated'),
            backgroundColor: Colors.green,
          ),
        );
        break;
      case 'delete':
        _showDeleteDialog(address);
        break;
    }
  }

  void _showDeleteDialog(Address address) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Address'),
        content: Text(
            'Are you sure you want to delete this address? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final addressProvider =
                  Provider.of<AddressProvider>(context, listen: false);
              final success = await addressProvider.deleteAddress(address.id);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Address deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete address'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Search Addresses'),
        content: TextField(
          decoration: InputDecoration(
            hintText: 'Enter name, city, or phone number',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
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
            child: Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Search'),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Filter Addresses'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AddressType?>(
              title: Text('All'),
              value: null,
              groupValue: _selectedType,
              onChanged: (value) {
                setState(() {
                  _selectedType = value;
                });
                Navigator.pop(context);
              },
            ),
            ...AddressType.values.map((type) {
              return RadioListTile<AddressType>(
                title: Text(_getTypeText(type)),
                value: type,
                groupValue: _selectedType,
                onChanged: (value) {
                  setState(() {
                    _selectedType = value;
                  });
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedType = null;
              });
              Navigator.pop(context);
            },
            child: Text('Clear Filter'),
          ),
        ],
      ),
    );
  }

  String _getTypeText(AddressType type) {
    switch (type) {
      case AddressType.home:
        return 'Home';
      case AddressType.work:
        return 'Work';
      case AddressType.other:
        return 'Other';
    }
  }
}
