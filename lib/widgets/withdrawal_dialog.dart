import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/withdrawal.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/wallet_provider.dart';
import 'package:ecommerce_int2/services/withdrawal_service.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Professional withdrawal/transfer dialog with enhanced UI
/// Allows users to withdraw funds to KPay, AYA Pay, Wave Pay, or Bank
class WithdrawalDialog extends StatefulWidget {
  const WithdrawalDialog({super.key});

  @override
  State<WithdrawalDialog> createState() => _WithdrawalDialogState();
}

class _WithdrawalDialogState extends State<WithdrawalDialog>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _accountNameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  late AnimationController _animationController;

  WithdrawalMethod _selectedMethod = WithdrawalMethod.kpay;
  bool _isProcessing = false;
  bool _showSuccessScreen = false;
  String? _errorMessage;
  double? _availableBalance;
  WithdrawalResult? _withdrawalResult;
  double? _withdrawnAmount;
  double? _previousBalance;
  double? _newBalance;
  String? _selectedBankName; // Selected bank name from dropdown

  // List of major banks in Myanmar
  static const List<String> _myanmarBanks = [
    'AYA Bank',
    'KBZ Bank',
    'CB Bank',
    'UAB Bank',
    'Yoma Bank',
    'Co-operative Bank (CB Bank)',
    'Myanmar Apex Bank',
    'Myanmar Citizens Bank',
    'Myanmar Oriental Bank',
    'First Private Bank',
    'United Amara Bank',
    'AGD Bank',
    'Innwa Bank',
    'MAB Bank',
    'Myanmar International Bank',
    'GTB Bank',
    'Shwe Rural & Urban Development Bank',
    'Thanlwin Bank',
    'Global Treasure Bank',
    'Asia Green Development Bank',
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Defer loading balance to avoid setState during build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadBalance();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _amountController.dispose();
    _accountNumberController.dispose();
    _accountNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Load current wallet balance
  Future<void> _loadBalance() async {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.isAuthenticated && authProvider.user != null) {
      final userId = authProvider.user!.id.toString();
      await walletProvider.loadBalance(userId, forceRefresh: true);
      if (mounted) {
        setState(() {
          _availableBalance = walletProvider.currentBalance;
          _previousBalance = walletProvider.currentBalance;
        });
      }
    }
  }

  /// Handle withdrawal method selection
  void _onMethodSelected(WithdrawalMethod method) {
    setState(() {
      _selectedMethod = method;
      _errorMessage = null;
      // Reset bank selection when switching away from bank method
      if (method != WithdrawalMethod.bank) {
        _selectedBankName = null;
      }
    });
    HapticFeedback.selectionClick();
  }

  /// Get label for account number field based on selected method
  String get _accountNumberLabel {
    if (_selectedMethod == WithdrawalMethod.bank) {
      return 'Account Number';
    }
    // All mobile payment methods use phone number
    return 'Phone Number';
  }

  /// Get hint for account number field
  String get _accountNumberHint {
    if (_selectedMethod == WithdrawalMethod.bank) {
      return 'Enter bank account number';
    }
    // All mobile payment methods use phone number format
    return 'Enter ${_selectedMethod.displayName} phone number (e.g., 09xxxxxxxxx)';
  }

  /// Show confirmation dialog before withdrawal
  Future<bool> _showConfirmationDialog(double amount) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Confirm Withdrawal',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please review your withdrawal details:',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                _buildConfirmationRow(
                  'Amount',
                  '${amount.toStringAsFixed(2)} Ks',
                ),
                const SizedBox(height: 8),
                _buildConfirmationRow('Method', _selectedMethod.displayName),
                const SizedBox(height: 8),
                // Show Bank Name for bank transfers, Pay Name for mobile payments
                if (_selectedMethod == WithdrawalMethod.bank &&
                    _selectedBankName != null) ...[
                  _buildConfirmationRow('Bank Name', _selectedBankName!),
                  const SizedBox(height: 8),
                ] else if (_selectedMethod != WithdrawalMethod.bank) ...[
                  _buildConfirmationRow(
                    'Pay Name',
                    _selectedMethod.displayName,
                  ),
                  const SizedBox(height: 8),
                ],
                _buildConfirmationRow(
                  _accountNumberLabel,
                  _accountNumberController.text.trim(),
                ),
                if (_accountNameController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildConfirmationRow(
                    'Account Name',
                    _accountNameController.text.trim(),
                  ),
                ],
                if (_availableBalance != null) ...[
                  const SizedBox(height: 8),
                  _buildConfirmationRow(
                    'Available Balance',
                    '${_availableBalance!.toStringAsFixed(2)} Ks',
                  ),
                  const SizedBox(height: 8),
                  _buildConfirmationRow(
                    'Balance After',
                    '${(_availableBalance! - amount).toStringAsFixed(2)} Ks',
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: mediumYellow,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildConfirmationRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
        ),
      ],
    );
  }

  /// Validate and submit withdrawal request
  Future<void> _submitWithdrawal() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.lightImpact();
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    if (!authProvider.isAuthenticated || authProvider.user == null) {
      _showError('Please login to withdraw funds');
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showError('Please enter a valid amount');
      return;
    }

    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog(amount);
    if (!confirmed) {
      return;
    }

    // Check withdrawal eligibility
    final eligibility = await walletProvider.checkWithdrawalEligibility(amount);
    if (!eligibility['eligible']) {
      _showError(eligibility['message'] ?? 'Cannot process withdrawal');
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    HapticFeedback.mediumImpact();

    try {
      final userId = authProvider.user!.id.toString();
      final accountNumber = _accountNumberController.text.trim();

      // Build withdrawal request
      final request = WithdrawalRequest(
        userId: userId,
        method: _selectedMethod,
        amount: amount,
        accountNumber: accountNumber,
        accountName: _accountNameController.text.trim().isEmpty
            ? null
            : _accountNameController.text.trim(),
        bankName: _selectedMethod == WithdrawalMethod.bank
            ? _selectedBankName
            : null,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      Logger.info(
        'Submitting withdrawal request: ${amount.toStringAsFixed(2)} Ks via ${_selectedMethod.displayName}',
        tag: 'WithdrawalDialog',
      );

      // Process withdrawal
      final result = await walletProvider.withdrawFromBalance(request);

      if (mounted) {
        if (result.success) {
          // Use result balance first (no need to reload immediately)
          final updatedBalance =
              result.newBalance ?? walletProvider.currentBalance;

          setState(() {
            _isProcessing = false;
            _showSuccessScreen = true;
            _withdrawalResult = result;
            _withdrawnAmount = amount;
            _previousBalance = _availableBalance;
            _newBalance = updatedBalance;
          });

          HapticFeedback.mediumImpact();
          _animationController.forward();

          // Refresh balance after state update (defer to avoid build conflicts)
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (mounted) {
              await walletProvider.loadBalance(userId, forceRefresh: true);
              if (mounted) {
                setState(() {
                  _newBalance = walletProvider.currentBalance;
                });
              }
            }
          });

          // Auto close after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              Navigator.of(context).pop(true);
              _showSuccessMessage();
            }
          });
        } else {
          setState(() {
            _isProcessing = false;
            _errorMessage = result.message;
          });
          HapticFeedback.heavyImpact();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Failed to process withdrawal. Please try again.';
        });
        HapticFeedback.heavyImpact();
        Logger.error(
          'Error submitting withdrawal: $e',
          tag: 'WithdrawalDialog',
        );
      }
    }
  }

  /// Show success message in SnackBar after dialog closes
  void _showSuccessMessage() {
    if (_withdrawnAmount != null && _newBalance != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Withdrawal Successful!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_withdrawnAmount!.toStringAsFixed(2)} Ks will be transferred to ${_selectedMethod.displayName}\n'
                  'Transaction ID: ${_withdrawalResult?.transactionId ?? "N/A"}\n'
                  'New Balance: ${_newBalance!.toStringAsFixed(2)} Ks',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      });
    }
  }

  /// Show error message
  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    // Build the appropriate screen based on state
    final content = _showSuccessScreen
        ? _buildSuccessScreen()
        : _buildFormScreen();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: Container(
          key: ValueKey(_showSuccessScreen ? 'success' : 'form'),
          child: content,
        ),
      ),
    );
  }

  /// Build success screen
  Widget _buildSuccessScreen() {
    return Container(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Success icon with animation
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green.shade600,
                    size: 60,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Withdrawal Successful!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: darkGrey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_withdrawnAmount != null &&
              _previousBalance != null &&
              _newBalance != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200, width: 2),
              ),
              child: Column(
                children: [
                  _buildSuccessRow(
                    'Amount Withdrawn',
                    '${_withdrawnAmount!.toStringAsFixed(2)} Ks',
                  ),
                  const Divider(height: 20),
                  _buildSuccessRow(
                    'Previous Balance',
                    '${_previousBalance!.toStringAsFixed(2)} Ks',
                  ),
                  const Divider(height: 20),
                  _buildSuccessRow(
                    'New Balance',
                    '${_newBalance!.toStringAsFixed(2)} Ks',
                    isHighlight: true,
                  ),
                  if (_withdrawalResult?.transactionId != null) ...[
                    const Divider(height: 20),
                    _buildSuccessRow(
                      'Transaction ID',
                      _withdrawalResult!.transactionId!,
                      isSmall: true,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Funds will be transferred to ${_selectedMethod.displayName} within 1-3 business days.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuccessRow(
    String label,
    String value, {
    bool isHighlight = false,
    bool isSmall = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isSmall ? 12 : 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isSmall ? 12 : (isHighlight ? 18 : 14),
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
            color: isHighlight ? Colors.green.shade700 : darkGrey,
          ),
        ),
      ],
    );
  }

  /// Build form screen
  Widget _buildFormScreen() {
    // Show loading indicator if balance is being loaded
    // Using consistent style with Hot Deals loading
    if (_availableBalance == null) {
      return Container(
        padding: const EdgeInsets.all(48.0),
        constraints: const BoxConstraints(minHeight: 200),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading wallet balance...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: mediumYellow.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet,
                        color: mediumYellow,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Withdraw Funds',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: darkGrey,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isProcessing
                          ? null
                          : () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Balance display card - always show if we have balance data
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.shade200,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Available Balance',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_availableBalance?.toStringAsFixed(2) ?? "0.00"} Ks',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 32,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Payment method selection
                const Text(
                  'Select Payment Method',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: darkGrey,
                  ),
                ),
                const SizedBox(height: 12),

                // Payment method cards in compact scrollable grid
                // Using GridView for better control and compact layout
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Responsive columns based on screen width
                    final screenWidth = constraints.maxWidth;
                    int crossAxisCount = 4; // Default 4 columns
                    double childAspectRatio = 0.85;

                    if (screenWidth < 350) {
                      // Very small screens: 3 columns
                      crossAxisCount = 3;
                      childAspectRatio = 0.90;
                    } else if (screenWidth > 500) {
                      // Larger screens: 4 columns with better spacing
                      crossAxisCount = 4;
                      childAspectRatio = 0.85;
                    }

                    // Calculate height based on number of rows needed
                    final itemCount = WithdrawalMethod.values.length;
                    final rowCount = (itemCount / crossAxisCount).ceil();
                    final calculatedHeight =
                        (rowCount * 80.0) + 16.0; // 80px per row + padding
                    const maxHeight = 180.0;
                    final gridHeight = calculatedHeight > maxHeight
                        ? maxHeight
                        : calculatedHeight;

                    return SizedBox(
                      height: gridHeight,
                      child: GridView.builder(
                        padding: EdgeInsets.zero,
                        scrollDirection: Axis.vertical,
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: childAspectRatio,
                        ),
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          final method = WithdrawalMethod.values[index];
                          return _buildCompactMethodCard(method);
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Amount field with better styling
                TextFormField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: 'Withdrawal Amount',
                    hintText: 'Enter amount',
                    prefixIcon: const Icon(Icons.attach_money),
                    suffixIcon: _amountController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _amountController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: mediumYellow,
                        width: 2,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.red.shade300),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}'),
                    ),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an amount';
                    }
                    final amount = double.tryParse(value.trim());
                    if (amount == null || amount <= 0) {
                      return 'Please enter a valid amount';
                    }
                    if (_availableBalance != null &&
                        amount > _availableBalance!) {
                      return 'Amount exceeds available balance';
                    }
                    if (amount < WithdrawalService.minWithdrawalAmount) {
                      return 'Minimum withdrawal is ${WithdrawalService.minWithdrawalAmount.toStringAsFixed(2)} Ks';
                    }
                    if (amount > WithdrawalService.maxWithdrawalAmount) {
                      return 'Maximum withdrawal is ${WithdrawalService.maxWithdrawalAmount.toStringAsFixed(2)} Ks';
                    }
                    return null;
                  },
                  enabled: !_isProcessing,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                // Account number field
                TextFormField(
                  controller: _accountNumberController,
                  decoration: InputDecoration(
                    labelText: _accountNumberLabel,
                    hintText: _accountNumberHint,
                    prefixIcon: const Icon(Icons.account_circle),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: mediumYellow,
                        width: 2,
                      ),
                    ),
                  ),
                  keyboardType: _selectedMethod == WithdrawalMethod.bank
                      ? TextInputType.number
                      : TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter $_accountNumberLabel';
                    }
                    return null;
                  },
                  enabled: !_isProcessing,
                ),
                const SizedBox(height: 16),

                // Account name field (optional)
                TextFormField(
                  controller: _accountNameController,
                  decoration: InputDecoration(
                    labelText: 'Account Holder Name (Optional)',
                    hintText: 'Enter account holder name',
                    prefixIcon: const Icon(Icons.person),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: mediumYellow,
                        width: 2,
                      ),
                    ),
                  ),
                  enabled: !_isProcessing,
                ),
                const SizedBox(height: 16),

                // Bank name dropdown (only for bank transfers)
                if (_selectedMethod == WithdrawalMethod.bank) ...[
                  DropdownButtonFormField<String>(
                    // Using initialValue per Flutter 3.33+ deprecation of 'value'
                    // This still allows dynamic updates through onChanged callback
                    initialValue: _selectedBankName,
                    decoration: InputDecoration(
                      labelText: 'Bank Name *',
                      hintText: 'Select your bank',
                      prefixIcon: const Icon(Icons.account_balance),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: mediumYellow,
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.red.shade300),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.red.shade400,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: darkGrey,
                    ),
                    iconEnabledColor: mediumYellow,
                    iconDisabledColor: Colors.grey.shade400,
                    isExpanded: true,
                    isDense: false,
                    style: const TextStyle(fontSize: 16, color: darkGrey),
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    menuMaxHeight: 300,
                    items: _myanmarBanks.map((String bank) {
                      return DropdownMenuItem<String>(
                        value: bank,
                        enabled: !_isProcessing,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.account_balance,
                                size: 20,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  bank,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: darkGrey,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: _isProcessing
                        ? null
                        : (String? newValue) {
                            setState(() {
                              _selectedBankName = newValue;
                              _errorMessage = null;
                            });
                            HapticFeedback.selectionClick();
                          },
                    validator: (value) {
                      if (_selectedMethod == WithdrawalMethod.bank &&
                          (value == null || value.trim().isEmpty)) {
                        return 'Please select a bank';
                      }
                      return null;
                    },
                    selectedItemBuilder: (BuildContext context) {
                      return _myanmarBanks.map((String bank) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            bank,
                            style: const TextStyle(
                              fontSize: 16,
                              color: darkGrey,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList();
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Notes field (optional)
                TextFormField(
                  controller: _notesController,
                  decoration: InputDecoration(
                    labelText: 'Notes (Optional)',
                    hintText: 'Add any additional notes',
                    prefixIcon: const Icon(Icons.note),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: mediumYellow,
                        width: 2,
                      ),
                    ),
                  ),
                  maxLines: 2,
                  enabled: !_isProcessing,
                ),
                const SizedBox(height: 24),

                // Error message with better styling
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.shade200,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red.shade700,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Submit button with improved design
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _submitWithdrawal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mediumYellow,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                      shadowColor: mediumYellow.withValues(alpha: 0.4),
                    ),
                    child: _isProcessing
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.8,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Processing...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Submit Withdrawal',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Get icon data and color for payment method
  Map<String, dynamic> _getMethodDetails(WithdrawalMethod method) {
    switch (method) {
      case WithdrawalMethod.kpay:
        return {'icon': Icons.phone_android, 'color': Colors.purple};
      case WithdrawalMethod.ayaPay:
        return {'icon': Icons.payment, 'color': Colors.blue};
      case WithdrawalMethod.wavePay:
        return {'icon': Icons.waves, 'color': Colors.green};
      case WithdrawalMethod.cbPay:
        return {'icon': Icons.account_balance_wallet, 'color': Colors.indigo};
      case WithdrawalMethod.uabPay:
        return {'icon': Icons.payment_outlined, 'color': Colors.teal};
      case WithdrawalMethod.onepay:
        return {'icon': Icons.monetization_on, 'color': Colors.amber};
      case WithdrawalMethod.trueMoney:
        return {'icon': Icons.money, 'color': Colors.deepOrange};
      case WithdrawalMethod.mpitesan:
        return {'icon': Icons.phone_iphone, 'color': Colors.pink};
      case WithdrawalMethod.yomaPay:
        return {'icon': Icons.wallet, 'color': Colors.cyan};
      case WithdrawalMethod.agdPay:
        return {'icon': Icons.mobile_friendly, 'color': Colors.lightGreen};
      case WithdrawalMethod.mabPay:
        return {'icon': Icons.credit_card, 'color': Colors.deepPurple};
      case WithdrawalMethod.bank:
        return {'icon': Icons.account_balance, 'color': Colors.orange};
    }
  }

  /// Build compact payment method selection card
  /// Designed for 4-column grid layout with professional styling
  Widget _buildCompactMethodCard(WithdrawalMethod method) {
    final isSelected = _selectedMethod == method;
    final details = _getMethodDetails(method);
    final icon = details['icon'] as IconData;
    final color = details['color'] as Color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isProcessing ? null : () => _onMethodSelected(method),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.12)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade300,
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Compact icon container
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.2)
                        : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? color : Colors.grey.shade600,
                    size: 22, // Smaller icon for compact design
                  ),
                ),
                const SizedBox(height: 6),
                // Compact text
                Flexible(
                  child: Text(
                    method.displayName,
                    style: TextStyle(
                      color: isSelected ? color : Colors.grey.shade700,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      fontSize: 10, // Smaller font for compact design
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Selection indicator
                if (isSelected) ...[
                  const SizedBox(height: 3),
                  Container(
                    width: 20,
                    height: 2,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
