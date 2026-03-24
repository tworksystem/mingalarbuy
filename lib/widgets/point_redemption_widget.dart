import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/services/point_service.dart';
import 'package:ecommerce_int2/app_properties.dart';

/// Widget for redeeming points during checkout
class PointRedemptionWidget extends StatefulWidget {
  final Function(int points, double discount)? onPointsRedeemed;
  final Function()? onPointsCleared;

  const PointRedemptionWidget({
    super.key,
    this.onPointsRedeemed,
    this.onPointsCleared,
  });

  @override
  _PointRedemptionWidgetState createState() => _PointRedemptionWidgetState();
}

class _PointRedemptionWidgetState extends State<PointRedemptionWidget> {
  int _selectedPoints = 0;
  bool _isRedeeming = false;

  @override
  Widget build(BuildContext context) {
    return Consumer2<PointProvider, CartProvider>(
      builder: (context, pointProvider, cartProvider, child) {
        final balance = pointProvider.balance;
        final cartTotal = cartProvider.totalPrice;
        
        if (balance == null || balance.currentBalance == 0) {
          return SizedBox.shrink();
        }

        final maxRedeemablePoints = PointService.calculateMaxRedeemablePoints(cartTotal);
        final availablePoints = balance.currentBalance;
        final canRedeem = availablePoints >= PointService.minRedemptionPoints;

        if (!canRedeem) {
          return SizedBox.shrink();
        }

        final maxPoints = availablePoints < maxRedeemablePoints 
            ? availablePoints 
            : maxRedeemablePoints;

        return Container(
          margin: EdgeInsets.all(16),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.stars,
                    color: mediumYellow,
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Redeem Points',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: darkGrey,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '${balance.currentBalance} pts',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: mediumYellow,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'You can redeem up to $maxPoints points (${PointService.maxRedemptionPercent}% of order total)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 16),
              
              // Quick selection buttons
              if (maxPoints >= PointService.minRedemptionPoints) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildQuickSelectButton(
                      'Use All',
                      maxPoints,
                      pointProvider,
                      cartProvider,
                    ),
                    if (maxPoints >= 500)
                      _buildQuickSelectButton(
                        '500 pts',
                        500,
                        pointProvider,
                        cartProvider,
                      ),
                    if (maxPoints >= 1000)
                      _buildQuickSelectButton(
                        '1000 pts',
                        1000,
                        pointProvider,
                        cartProvider,
                      ),
                    if (maxPoints >= 2000)
                      _buildQuickSelectButton(
                        '2000 pts',
                        2000,
                        pointProvider,
                        cartProvider,
                      ),
                  ],
                ),
                SizedBox(height: 12),
              ],

              // Custom amount input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Custom amount',
                        hintText: 'Enter points (min ${PointService.minRedemptionPoints})',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: Icon(Icons.confirmation_number),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final points = int.tryParse(value) ?? 0;
                        if (points >= PointService.minRedemptionPoints && 
                            points <= maxPoints) {
                          setState(() {
                            _selectedPoints = points;
                          });
                        }
                      },
                    ),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _selectedPoints >= PointService.minRedemptionPoints &&
                            !_isRedeeming
                        ? () => _applyPoints(_selectedPoints, pointProvider, cartProvider)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mediumYellow,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    child: _isRedeeming
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text('Apply'),
                  ),
                ],
              ),

              // Discount preview
              if (_selectedPoints > 0) ...[
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: mediumYellow.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Discount Applied:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: darkGrey,
                        ),
                      ),
                      Text(
                        '-${PointService.calculateDiscountFromPoints(_selectedPoints).toStringAsFixed(2)} Ks',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Clear button
              if (_selectedPoints > 0) ...[
                SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedPoints = 0;
                    });
                    widget.onPointsCleared?.call();
                  },
                  icon: Icon(Icons.clear, size: 18),
                  label: Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickSelectButton(
    String label,
    int points,
    PointProvider pointProvider,
    CartProvider cartProvider,
  ) {
    final isSelected = _selectedPoints == points;
    
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _selectedPoints = points;
        });
        _applyPoints(points, pointProvider, cartProvider);
      },
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: isSelected ? mediumYellow : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
        backgroundColor: isSelected ? mediumYellow.withOpacity(0.1) : Colors.transparent,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? mediumYellow : darkGrey,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Future<void> _applyPoints(
    int points,
    PointProvider pointProvider,
    CartProvider cartProvider,
  ) async {
    if (_isRedeeming) return;

    final cartTotal = cartProvider.totalPrice;
    
    // Validate
    if (!PointService.isValidRedemptionAmount(
      points,
      cartTotal,
      pointProvider.currentBalance,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid redemption amount. Maximum ${PointService.calculateMaxRedeemablePoints(cartTotal)} points allowed.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isRedeeming = true;
    });

    final discount = PointService.calculateDiscountFromPoints(points);
    
    // Notify parent
    widget.onPointsRedeemed?.call(points, discount);

    setState(() {
      _isRedeeming = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$points points applied! ${discount.toStringAsFixed(2)} Ks discount'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

