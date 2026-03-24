import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/wallet_provider.dart';
import 'package:ecommerce_int2/services/prize_code_service.dart';
import 'package:ecommerce_int2/services/wallet_service.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Prize code input dialog with real-time validation
class PrizeCodeDialog extends StatefulWidget {
  const PrizeCodeDialog({super.key});

  @override
  State<PrizeCodeDialog> createState() => _PrizeCodeDialogState();
}

class _PrizeCodeDialogState extends State<PrizeCodeDialog> {
  final TextEditingController _codeController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isClaiming = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Claim the prize code
  Future<void> _claimPrize() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a gift code';
      });
      return;
    }

    // One-time validation when user taps Claim
    setState(() {
      _isClaiming = true;
      _errorMessage = null;
    });

    PrizeCodeValidationResult? validationResult;
    try {
      validationResult = await PrizeCodeService.validatePrizeCode(code);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isClaiming = false;
          _errorMessage = 'Failed to validate code. Please try again.';
        });
      }
      return;
    }

    if (validationResult == null || !validationResult.isValid) {
      if (mounted) {
        setState(() {
          _isClaiming = false;
          _errorMessage =
              validationResult?.message ?? 'Invalid code. Please try again.';
        });
      }
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    if (!authProvider.isAuthenticated || authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to claim prizes'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final userId = authProvider.user!.id.toString();

      // Claim prize code - this only affects wallet balance, not points
      final claimResult = await PrizeCodeService.claimPrizeCode(userId, code);

      if (mounted) {
        if (claimResult.success) {
          final prizeValue = claimResult.prizeValue ?? 0.0;

          // Validate prize value
          if (prizeValue <= 0) {
            Logger.error('Invalid prize value received: $prizeValue',
                tag: 'PrizeCodeDialog');
            setState(() {
              _isClaiming = false;
              _errorMessage = 'Invalid prize value. Please try again.';
            });
            return;
          }

          // Prize codes ONLY update wallet balance, never points
          // Backend already updated the wallet balance and returned new_wallet_balance
          Logger.info(
            'Claiming prize code: $code - Prize value: \$${prizeValue.toStringAsFixed(2)} (NOT points)',
            tag: 'PrizeCodeDialog',
          );

          // Get current balance before update for validation
          final balanceBefore = walletProvider.currentBalance;
          Logger.info(
              'Balance before update: \$${balanceBefore.toStringAsFixed(2)}',
              tag: 'PrizeCodeDialog');

          // CRITICAL FIX: Use backend-returned balance if available
          // The backend /wp-json/twork/v1/prize/claim already updated the wallet balance
          // We should use that balance instead of calling addToBalance() again to prevent double-updating
          WalletUpdateResult updateResult;

          if (claimResult.newWalletBalance != null &&
              claimResult.newWalletBalance! >= 0) {
            // Backend already updated the balance - use the returned value
            // This is the correct approach: backend updated it, we just sync the provider
            Logger.info(
                '✅ Backend returned new wallet balance: \$${claimResult.newWalletBalance!.toStringAsFixed(2)}. '
                'Updating provider directly (backend already updated database).',
                tag: 'PrizeCodeDialog');

            updateResult = await walletProvider.updateBalanceFromClaim(
              userId,
              claimResult.newWalletBalance!,
              'Prize code: $code',
            );
          } else {
            // Fallback: Backend didn't return balance (test codes, API issue, or legacy response)
            // Use addToBalance as fallback - this will call the wallet/add API endpoint
            Logger.info(
                '⚠️ Backend did not return new_wallet_balance. Using addToBalance as fallback. '
                'This may cause double-updating if backend already updated the balance.',
                tag: 'PrizeCodeDialog');

            updateResult = await walletProvider.addToBalance(
              prizeValue,
              'Prize code: $code',
            );
          }

          // Verify the update was successful
          if (updateResult.success && updateResult.newBalance != null) {
            var newBalance = updateResult.newBalance!.currentBalance;

            // Validate balance increased (with tolerance for rounding)
            final expectedMinBalance = balanceBefore + prizeValue - 0.01;
            final expectedMaxBalance = balanceBefore + prizeValue + 0.01;

            if (newBalance < expectedMinBalance ||
                newBalance > expectedMaxBalance) {
              Logger.warning(
                  'Balance validation: Expected ~\$${(balanceBefore + prizeValue).toStringAsFixed(2)}, Got: \$${newBalance.toStringAsFixed(2)}',
                  tag: 'PrizeCodeDialog');

              // Use provider balance as source of truth
              final providerBalance = walletProvider.currentBalance;
              if (providerBalance >= expectedMinBalance &&
                  providerBalance <= expectedMaxBalance) {
                Logger.info(
                    'Using provider balance: \$${providerBalance.toStringAsFixed(2)}',
                    tag: 'PrizeCodeDialog');
                newBalance = providerBalance;
              }
            }

            Logger.info(
                '✅ Prize claimed successfully! New balance: \$${newBalance.toStringAsFixed(2)} (was \$${balanceBefore.toStringAsFixed(2)}, added \$${prizeValue.toStringAsFixed(2)})',
                tag: 'PrizeCodeDialog');

            // Final verification: ensure provider balance matches
            final finalProviderBalance = walletProvider.currentBalance;
            if ((finalProviderBalance - newBalance).abs() > 0.01) {
              Logger.warning(
                  'Final balance check: Result \$${newBalance.toStringAsFixed(2)} vs Provider \$${finalProviderBalance.toStringAsFixed(2)}. Using provider.',
                  tag: 'PrizeCodeDialog');
              newBalance = finalProviderBalance;
            }

            // Show success message with wallet value
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${claimResult.message}\n\$${prizeValue.toStringAsFixed(2)} added to wallet!\nNew balance: \$${newBalance.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );

            // CRITICAL: Ensure UI updates - close dialog first
            Navigator.of(context).pop(true);

            // Refresh user data to get updated My Rewards and My Points
            try {
              await authProvider.refreshUser();
              Logger.info('User data refreshed after prize claim',
                  tag: 'PrizeCodeDialog');
            } catch (e) {
              Logger.warning('Failed to refresh user data: $e',
                  tag: 'PrizeCodeDialog');
            }

            // Trigger notifications to ensure Consumer widgets rebuild
            final walletProviderInstance = WalletProvider.instance;

            // Immediate notification after dialog closes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              walletProviderInstance.forceNotifyListeners();
              Logger.info(
                  'Post-dialog notification sent. Balance: \$${walletProviderInstance.currentBalance.toStringAsFixed(2)}',
                  tag: 'PrizeCodeDialog');
            });
          } else {
            Logger.error(
                'addToBalance failed! Success: ${updateResult.success}, Message: ${updateResult.message}, NewBalance: ${updateResult.newBalance?.currentBalance}',
                tag: 'PrizeCodeDialog');

            // If addToBalance failed, check if balance was still updated
            final balanceAfter = walletProvider.currentBalance;
            final balanceIncreased = balanceAfter > balanceBefore;

            if (balanceIncreased) {
              // Balance was updated even though result says failed - show success
              Logger.info(
                  'Balance was updated despite failed result. Balance: \$${balanceAfter.toStringAsFixed(2)}',
                  tag: 'PrizeCodeDialog');

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${claimResult.message}\n\$${prizeValue.toStringAsFixed(2)} added to wallet!\nNew balance: \$${balanceAfter.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 4),
                ),
              );
              Navigator.of(context).pop(true);

              // Refresh user data to get updated My Rewards and My Points
              try {
                await authProvider.refreshUser();
                Logger.info('User data refreshed after prize claim (fallback)',
                    tag: 'PrizeCodeDialog');
              } catch (e) {
                Logger.warning('Failed to refresh user data: $e',
                    tag: 'PrizeCodeDialog');
              }

              // Notify listeners
              WidgetsBinding.instance.addPostFrameCallback((_) {
                WalletProvider.instance.forceNotifyListeners();
              });
            } else {
              // Update failed - try to refresh from API as last resort
              // The backend might have updated the balance even if our provider update failed
              Logger.info(
                  'Balance update returned failure. Refreshing from API to check server state.',
                  tag: 'PrizeCodeDialog');

              // Force refresh from server (bypasses cache and recent update protection)
              await walletProvider.loadBalance(userId, forceRefresh: true);

              // Wait a bit for the refresh to complete
              await Future.delayed(const Duration(milliseconds: 300));

              final refreshedBalance = walletProvider.currentBalance;
              final balanceIncreased = refreshedBalance > balanceBefore;

              if (balanceIncreased) {
                // Balance was updated on server despite provider failure
                Logger.info(
                    '✅ Balance was updated on server! Refreshed balance: \$${refreshedBalance.toStringAsFixed(2)} (was \$${balanceBefore.toStringAsFixed(2)})',
                    tag: 'PrizeCodeDialog');

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${claimResult.message}\n\$${prizeValue.toStringAsFixed(2)} added to wallet!\nNew balance: \$${refreshedBalance.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 4),
                  ),
                );
                Navigator.of(context).pop(true);

                // Refresh user data to get updated My Rewards and My Points
                try {
                  final authProvider =
                      Provider.of<AuthProvider>(context, listen: false);
                  await authProvider.refreshUser();
                  Logger.info(
                      'User data refreshed after prize claim (last resort)',
                      tag: 'PrizeCodeDialog');
                } catch (e) {
                  Logger.warning('Failed to refresh user data: $e',
                      tag: 'PrizeCodeDialog');
                }

                // Ensure UI updates
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  WalletProvider.instance.forceNotifyListeners();
                });
              } else {
                // Balance update truly failed - show error
                setState(() {
                  _isClaiming = false;
                  _errorMessage = updateResult.message.isNotEmpty
                      ? updateResult.message
                      : 'Failed to update wallet balance. The prize was claimed but the balance was not updated. Please refresh the app or contact support.';
                });
                Logger.error(
                    '❌ Balance update failed completely. Balance before: \$${balanceBefore.toStringAsFixed(2)}, Balance after: \$${refreshedBalance.toStringAsFixed(2)}. Prize was claimed but balance not updated.',
                    tag: 'PrizeCodeDialog');
              }
            }
          }
        } else {
          setState(() {
            _isClaiming = false;
            _errorMessage = claimResult.message;
          });
        }
      }
    } catch (e, stackTrace) {
      Logger.error('Error claiming prize code: $e',
          tag: 'PrizeCodeDialog', error: e, stackTrace: stackTrace);

      if (mounted) {
        // Try to refresh balance in case backend updated it despite the error
        try {
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
          if (authProvider.isAuthenticated && authProvider.user != null) {
            final userId = authProvider.user!.id.toString();
            await walletProvider.loadBalance(userId, forceRefresh: true);
            final refreshedBalance = walletProvider.currentBalance;

            // If balance is positive, the prize might have been claimed successfully
            // Show a message asking user to check their balance
            if (refreshedBalance > 0) {
              // Also refresh user data to get updated My Rewards and My Points
              try {
                await authProvider.refreshUser();
                Logger.info(
                    'User data refreshed after prize claim (error case)',
                    tag: 'PrizeCodeDialog');
              } catch (e) {
                Logger.warning('Failed to refresh user data: $e',
                    tag: 'PrizeCodeDialog');
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Prize claim may have succeeded. Please check your wallet balance.',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        } catch (refreshError) {
          Logger.error(
              'Error refreshing balance after claim error: $refreshError',
              tag: 'PrizeCodeDialog');
        }

        setState(() {
          _isClaiming = false;
          _errorMessage =
              'Failed to claim prize. Please try again. If the issue persists, please check your wallet balance.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              physics: ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Gift Code',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: darkGrey,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your gift code to claim rewards',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Code input field
                  TextFormField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: 'Gift Code',
                      hintText: 'Enter gift code here',
                      prefixIcon: const Icon(Icons.card_giftcard),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: mediumYellow,
                          width: 2,
                        ),
                      ),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a gift code';
                      }
                      return null;
                    },
                    enabled: !_isClaiming,
                  ),

                  // Error message
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Claim button
                  ElevatedButton(
                    onPressed: _isClaiming ? null : _claimPrize,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mediumYellow,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isClaiming
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Claim Prize',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  SizedBox(height: 8), // Minimal bottom padding
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
