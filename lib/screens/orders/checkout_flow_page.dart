import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/providers/address_provider.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/models/address.dart';
import 'package:ecommerce_int2/models/order.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/screens/orders/order_confirmation_page.dart';

class CheckoutFlowPage extends StatefulWidget {
  const CheckoutFlowPage({super.key});

  @override
  _CheckoutFlowPageState createState() => _CheckoutFlowPageState();
}

class _CheckoutFlowPageState extends State<CheckoutFlowPage> {
  // Payment-only checkout flow: start at Payment step directly.
  int _currentStep = 0;
  Address? _selectedShippingAddress;
  Address? _selectedBillingAddress;
  // Default to a Myanmar-friendly method (avoid card types).
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cashOnDelivery;

  // Current contact phone for this order/payment
  final TextEditingController _contactPhoneController = TextEditingController();
  String? _contactPhoneError;
  String _contactPhone = '';

  // Myanmar-specific payment options
  final List<String> _myanmarMobilePayments = const [
    // Telco wallets
    'KBZPay',
    'WavePay',
    'AYA Pay',
    'CB Pay',
    'OnePay',
    'MytelPay',
    'OK Dollar',
    'M-Pitesan',
    // Bank / fintech wallets
    'AGD Pay',
    'AYAPay Wallet',
    'AYA iBanking',
    'CB mBanking',
    'Yoma Bank Mobile',
    'MAB Mobile Banking',
    'UAB Pay',
    'A Bank Mobile',
  ];

  final List<String> _myanmarBanks = const [
    // Major private banks
    'KBZ Bank',
    'AYA Bank',
    'CB Bank',
    'Yoma Bank',
    'AGD Bank',
    'MAB Bank',
    'UAB Bank',
    'A Bank',
    'Innwa Bank',
    'Shwe Bank',
    'Myanmar Citizens Bank (MCB)',
    'Myanmar Apex Bank (MAB)',
    'Ayeyarwaddy Farmers Development Bank (A Bank)',
    // State / other banks
    'Myanmar Economic Bank (MEB)',
    'Myanmar Foreign Trade Bank (MFTB)',
    'Myanma Investment and Commercial Bank (MICB)',
    // Military / joint-venture banks
    'Myawaddy Bank',
    'Innwa Bank',
    'Asia Green Development Bank (AGD)',
  ];

  String? _selectedMobilePaymentProvider;
  String? _selectedBankName;

  @override
  void initState() {
    super.initState();
    // Auto-fill phone number from user profile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserPhone();
    });
  }

  void _loadUserPhone() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated && authProvider.user != null) {
      final userPhone = authProvider.user!.phone;
      if (userPhone != null && userPhone.isNotEmpty) {
        if (mounted) {
          setState(() {
            _contactPhoneController.text = userPhone.trim();
            _contactPhone = userPhone.trim();
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _contactPhoneController.dispose();
    super.dispose();
  }

  Future<void> _onRefreshCheckout() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated) {
      await authProvider.refreshUser();
      // Reload phone number after refresh
      _loadUserPhone();
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        iconTheme: IconThemeData(color: darkGrey),
        title: Text(
          'Checkout',
          style: TextStyle(
            color: darkGrey,
            fontWeight: FontWeight.w500,
            fontSize: 18.0,
          ),
        ),
      ),
      body: Consumer<CartProvider>(
        builder: (context, cartProvider, child) {
          final bool shouldShowEmptyState =
              cartProvider.isEmpty && _currentStep != 3;

          if (shouldShowEmptyState) {
            return _buildEmptyCartState();
          }

          return Column(
            children: [
              _buildProgressIndicator(),
              Expanded(
                child: _buildCurrentStep(cartProvider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyCartState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 100,
            color: Colors.grey[300],
          ),
          SizedBox(height: 20),
          Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Add some items to your cart first',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          _buildStepIndicator(0, 'Payment', _currentStep >= 0),
          _buildStepConnector(_currentStep > 0),
          _buildStepIndicator(1, 'Confirm', _currentStep >= 1),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isActive ? mediumYellow : Colors.grey[300],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${step + 1}',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[600],
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? mediumYellow : Colors.grey[600],
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector(bool isActive) {
    return Expanded(
      child: Container(
        height: 2,
        color: isActive ? mediumYellow : Colors.grey[300],
        margin: EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _buildCurrentStep(CartProvider cartProvider) {
    switch (_currentStep) {
      case 0:
        return _buildPaymentStep();
      case 1:
        return _buildConfirmationStep();
      default:
        return _buildPaymentStep();
    }
  }

  Widget _buildPaymentStep() {
    return Consumer<AddressProvider>(
      builder: (context, addressProvider, child) {
        final hasAddresses = addressProvider.hasAddresses;

        // Auto-select default address (or first) in the background so WooCommerce still gets a valid address.
        if (hasAddresses && _selectedShippingAddress == null) {
          final addresses = addressProvider.addresses;
          final chosen = addresses.firstWhere(
            (a) => a.isDefault,
            orElse: () => addresses.first,
          );
          _selectedShippingAddress = chosen;
          _selectedBillingAddress = chosen;
        }

        return RefreshIndicator(
          onRefresh: _onRefreshCheckout,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasAddresses) ...[
                  _buildNoAddressState(),
                  SizedBox(height: 20),
                ],
                _buildContactPhoneField(),
                SizedBox(height: 20),
                Text(
                  'Select Payment Method',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: darkGrey,
                  ),
                ),
                SizedBox(height: 20),
                ...PaymentMethod.values
                    .where(
                      (m) =>
                          m != PaymentMethod.creditCard &&
                          m != PaymentMethod.debitCard,
                    )
                    .map((method) => _buildPaymentMethodCard(method)),
                SizedBox(height: 16),
                if (_selectedPaymentMethod == PaymentMethod.mobilePayment)
                  _buildMobilePaymentDetails(),
                if (_selectedPaymentMethod == PaymentMethod.bankTransfer)
                  _buildBankTransferDetails(),
                SizedBox(height: 30),
                _buildNextButton('Review Order', () {
                  if (_validatePaymentStep()) {
                    setState(() {
                      _currentStep = 1;
                    });
                  }
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConfirmationStep() {
    return OrderConfirmationPage(
      selectedShippingAddress: _selectedShippingAddress,
      selectedBillingAddress: _selectedBillingAddress,
      selectedPaymentMethod: _selectedPaymentMethod,
      contactPhone: _contactPhone,
      mobilePaymentProvider: _selectedMobilePaymentProvider,
      bankName: _selectedBankName,
    );
  }

  Widget _buildNoAddressState() {
    return Container(
      padding: EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Icon(
            Icons.location_off,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'No addresses found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'You can continue without adding an address.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard(PaymentMethod method) {
    final isSelected = _selectedPaymentMethod == method;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = method;
          if (method != PaymentMethod.mobilePayment) {
            _selectedMobilePaymentProvider = null;
          }
          if (method != PaymentMethod.bankTransfer) {
            _selectedBankName = null;
          }
        });
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? mediumYellow.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? mediumYellow : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              _getPaymentMethodIcon(method),
              color: isSelected ? mediumYellow : Colors.grey[600],
              size: 24,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                _getPaymentMethodText(method),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? mediumYellow : darkGrey,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: mediumYellow,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: mediumYellow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  IconData _getPaymentMethodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.creditCard:
        return Icons.credit_card;
      case PaymentMethod.debitCard:
        return Icons.account_balance_wallet;
      case PaymentMethod.mobilePayment:
        return Icons.phone_android;
      case PaymentMethod.bankTransfer:
        return Icons.account_balance;
      case PaymentMethod.cashOnDelivery:
        return Icons.money;
    }
  }

  String _getPaymentMethodText(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.creditCard:
        return 'Credit Card';
      case PaymentMethod.debitCard:
        return 'Debit Card';
      case PaymentMethod.mobilePayment:
        return 'Mobile Payment';
      case PaymentMethod.bankTransfer:
        return 'Bank Transfer';
      case PaymentMethod.cashOnDelivery:
        return 'Cash on Delivery';
    }
  }

  Widget _buildContactPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.phone_android, color: mediumYellow, size: 20),
            SizedBox(width: 8),
            Text(
              'Current Contact Phone',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: darkGrey,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        TextField(
          controller: _contactPhoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: 'Enter your current phone number',
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: mediumYellow),
            ),
            errorText: _contactPhoneError,
            prefixIcon: Icon(Icons.phone, color: Colors.grey[600]),
          ),
          onChanged: (_) {
            if (_contactPhoneError != null) {
              setState(() {
                _contactPhoneError = null;
              });
            }
          },
        ),
      ],
    );
  }

  bool _validateContactPhone({bool showSnackBar = false}) {
    final phone = _contactPhoneController.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _contactPhoneError = 'Please enter your current contact phone.';
      });
      if (showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please enter your current contact phone.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    setState(() {
      _contactPhoneError = null;
      _contactPhone = phone;
    });
    return true;
  }

  bool _validatePaymentStep() {
    if (!_validateContactPhone(showSnackBar: true)) {
      return false;
    }

    if (_selectedPaymentMethod == PaymentMethod.mobilePayment &&
        _selectedMobilePaymentProvider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a mobile payment provider.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    if (_selectedPaymentMethod == PaymentMethod.bankTransfer &&
        _selectedBankName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a bank for transfer.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    return true;
  }

  Widget _buildMobilePaymentDetails() {
    return Card(
      elevation: 2,
      margin: EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mobile Payment (Myanmar)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: darkGrey,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Choose the wallet you will use to pay.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                color: Colors.white,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMobilePaymentProvider,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  hint: Text('Select mobile payment method'),
                  items: _myanmarMobilePayments
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p,
                          child: Text(p),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedMobilePaymentProvider = value;
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankTransferDetails() {
    return Card(
      elevation: 2,
      margin: EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bank Transfer (Myanmar)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: darkGrey,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Select the bank account you will transfer to.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                color: Colors.white,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedBankName,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  hint: Text('Select bank for transfer'),
                  items: _myanmarBanks
                      .map(
                        (b) => DropdownMenuItem<String>(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedBankName = value;
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
