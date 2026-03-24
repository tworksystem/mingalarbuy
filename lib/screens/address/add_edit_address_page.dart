import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/providers/address_provider.dart';
import 'package:ecommerce_int2/models/address.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';

class AddEditAddressPage extends StatefulWidget {
  final Address? address;

  const AddEditAddressPage({super.key, this.address});

  @override
  _AddEditAddressPageState createState() => _AddEditAddressPageState();
}

class _AddEditAddressPageState extends State<AddEditAddressPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Form controllers
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _companyController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();

  // Form state
  AddressType _selectedType = AddressType.home;
  bool _isDefault = false;
  bool _isLoading = false;

  // Countries list for dropdown
  final List<String> _countries = [
    'United States',
    'Canada',
    'United Kingdom',
    'Australia',
    'Germany',
    'France',
    'Italy',
    'Spain',
    'Netherlands',
    'Belgium',
    'Switzerland',
    'Austria',
    'Sweden',
    'Norway',
    'Denmark',
    'Finland',
    'Ireland',
    'Portugal',
    'Greece',
    'Poland',
    'Czech Republic',
    'Hungary',
    'Romania',
    'Bulgaria',
    'Croatia',
    'Slovenia',
    'Slovakia',
    'Estonia',
    'Latvia',
    'Lithuania',
    'Japan',
    'South Korea',
    'China',
    'India',
    'Brazil',
    'Mexico',
    'Argentina',
    'Chile',
    'Colombia',
    'Peru',
    'Venezuela',
    'Ecuador',
    'Uruguay',
    'Paraguay',
    'Bolivia',
    'South Africa',
    'Egypt',
    'Nigeria',
    'Kenya',
    'Morocco',
    'Tunisia',
    'Algeria',
    'Ghana',
    'Ethiopia',
    'Uganda',
    'Tanzania',
    'Zimbabwe',
    'Botswana',
    'Namibia',
    'Zambia',
    'Malawi',
    'Mozambique',
    'Angola',
    'Cameroon',
    'Senegal',
    'Ivory Coast',
    'Mali',
    'Burkina Faso',
    'Niger',
    'Chad',
    'Sudan',
    'Libya',
    'Somalia',
    'Djibouti',
    'Eritrea',
    'Rwanda',
    'Burundi',
    'Central African Republic',
    'Democratic Republic of the Congo',
    'Republic of the Congo',
    'Gabon',
    'Equatorial Guinea',
    'Sao Tome and Principe',
    'Cape Verde',
    'Guinea-Bissau',
    'Guinea',
    'Sierra Leone',
    'Liberia',
    'Gambia',
    'Mauritania',
    'Western Sahara',
    'Madagascar',
    'Mauritius',
    'Seychelles',
    'Comoros',
    'Mayotte',
    'Reunion',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  void _initializeForm() {
    if (widget.address != null) {
      // Editing existing address
      final address = widget.address!;
      _firstNameController.text = address.firstName;
      _lastNameController.text = address.lastName;
      _companyController.text = address.company;
      _addressLine1Controller.text = address.addressLine1;
      _addressLine2Controller.text = address.addressLine2;
      _cityController.text = address.city;
      _stateController.text = address.state;
      _postalCodeController.text = address.postalCode;
      _countryController.text = address.country;
      _phoneController.text = address.phone;
      _emailController.text = address.email;
      _notesController.text = address.notes ?? '';
      _selectedType = address.type;
      _isDefault = address.isDefault;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.address != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        iconTheme: IconThemeData(color: darkGrey),
        title: Text(
          isEditing ? 'Edit Address' : 'Add Address',
          style: TextStyle(
            color: darkGrey,
            fontWeight: FontWeight.w500,
            fontSize: 18.0,
          ),
        ),
        actions: [
          if (isEditing)
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: _showDeleteDialog,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: AppPullToRefresh(
                // Safe refresh: do not clear inputs; just re-render.
                onRefresh: () async {
                  if (!mounted) return;
                  setState(() {});
                },
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPersonalInfoSection(),
                      SizedBox(height: 24),
                      _buildAddressSection(),
                      SizedBox(height: 24),
                      _buildContactSection(),
                      SizedBox(height: 24),
                      _buildTypeSection(),
                      SizedBox(height: 24),
                      _buildNotesSection(),
                      SizedBox(height: 100), // Space for floating button
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _saveAddress,
        backgroundColor: mediumYellow,
        icon: _isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(Icons.save, color: Colors.white),
        label: Text(
          isEditing ? 'Update Address' : 'Save Address',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    return _buildSection(
      title: 'Personal Information',
      icon: Icons.person,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _firstNameController,
                label: 'First Name',
                hint: 'Enter first name',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'First name is required';
                  }
                  return null;
                },
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _lastNameController,
                label: 'Last Name',
                hint: 'Enter last name',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Last name is required';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        _buildTextField(
          controller: _companyController,
          label: 'Company (Optional)',
          hint: 'Enter company name',
        ),
      ],
    );
  }

  Widget _buildAddressSection() {
    return _buildSection(
      title: 'Address Information',
      icon: Icons.location_on,
      children: [
        _buildTextField(
          controller: _addressLine1Controller,
          label: 'Address Line 1',
          hint: 'Street address, P.O. box',
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Address line 1 is required';
            }
            return null;
          },
        ),
        SizedBox(height: 16),
        _buildTextField(
          controller: _addressLine2Controller,
          label: 'Address Line 2 (Optional)',
          hint: 'Apartment, suite, unit, building, floor, etc.',
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildTextField(
                controller: _cityController,
                label: 'City',
                hint: 'Enter city',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'City is required';
                  }
                  return null;
                },
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _stateController,
                label: 'State/Province',
                hint: 'State',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'State is required';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _postalCodeController,
                label: 'Postal Code',
                hint: 'ZIP/Postal code',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Postal code is required';
                  }
                  return null;
                },
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: _buildDropdownField(
                controller: _countryController,
                label: 'Country',
                hint: 'Select country',
                items: _countries,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Country is required';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContactSection() {
    return _buildSection(
      title: 'Contact Information',
      icon: Icons.contact_phone,
      children: [
        _buildTextField(
          controller: _phoneController,
          label: 'Phone Number',
          hint: 'Enter phone number',
          keyboardType: TextInputType.phone,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Phone number is required';
            }
            if (value.length < 10) {
              return 'Please enter a valid phone number';
            }
            return null;
          },
        ),
        SizedBox(height: 16),
        _buildTextField(
          controller: _emailController,
          label: 'Email (Optional)',
          hint: 'Enter email address',
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                  .hasMatch(value)) {
                return 'Please enter a valid email address';
              }
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildTypeSection() {
    return _buildSection(
      title: 'Address Type',
      icon: Icons.category,
      children: [
        Row(
          children: AddressType.values.map((type) {
            return Expanded(
              child: RadioListTile<AddressType>(
                title: Text(_getTypeText(type)),
                subtitle: Text(_getTypeDescription(type)),
                value: type,
                groupValue: _selectedType,
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                  });
                },
                activeColor: mediumYellow,
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 16),
        SwitchListTile(
          title: Text(
            'Set as Default Address',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            'This address will be used for future orders',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          value: _isDefault,
          onChanged: (value) {
            setState(() {
              _isDefault = value;
            });
          },
          activeThumbColor: mediumYellow,
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return _buildSection(
      title: 'Additional Notes',
      icon: Icons.note,
      children: [
        _buildTextField(
          controller: _notesController,
          label: 'Notes (Optional)',
          hint: 'Any additional delivery instructions or notes',
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: mediumYellow, size: 20),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: darkGrey,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: mediumYellow, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
    );
  }

  Widget _buildDropdownField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required List<String> items,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: controller.text.isNotEmpty ? controller.text : null,
      // Prevent RenderFlex overflow by forcing the dropdown to take full width
      // and gracefully ellipsizing long text instead of expanding past bounds.
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: mediumYellow, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
      validator: validator,
      items: items.map((String item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(
            item,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
      }).toList(),
      onChanged: (String? value) {
        controller.text = value ?? '';
      },
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

  String _getTypeDescription(AddressType type) {
    switch (type) {
      case AddressType.home:
        return 'Residential address';
      case AddressType.work:
        return 'Office or workplace';
      case AddressType.other:
        return 'Other location';
    }
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final addressProvider =
          Provider.of<AddressProvider>(context, listen: false);

      if (widget.address != null) {
        // Update existing address
        final success = await addressProvider.updateAddress(
          addressId: widget.address!.id,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          company: _companyController.text.trim(),
          addressLine1: _addressLine1Controller.text.trim(),
          addressLine2: _addressLine2Controller.text.trim(),
          city: _cityController.text.trim(),
          state: _stateController.text.trim(),
          postalCode: _postalCodeController.text.trim(),
          country: _countryController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          type: _selectedType,
          isDefault: _isDefault,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
        );

        if (success != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Address updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        } else {
          _showErrorSnackBar('Failed to update address');
        }
      } else {
        // Add new address
        final success = await addressProvider.addAddress(
          userId:
              'current_user', // You might want to get this from auth provider
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          company: _companyController.text.trim(),
          addressLine1: _addressLine1Controller.text.trim(),
          addressLine2: _addressLine2Controller.text.trim(),
          city: _cityController.text.trim(),
          state: _stateController.text.trim(),
          postalCode: _postalCodeController.text.trim(),
          country: _countryController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          type: _selectedType,
          isDefault: _isDefault,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
        );

        if (success != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Address added successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        } else {
          _showErrorSnackBar('Failed to add address');
        }
      }
    } catch (e) {
      _showErrorSnackBar('An error occurred: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Address'),
        content: Text(
          'Are you sure you want to delete this address? This action cannot be undone.',
        ),
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
              final success =
                  await addressProvider.deleteAddress(widget.address!.id);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Address deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.of(context).pop();
              } else {
                _showErrorSnackBar('Failed to delete address');
              }
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
