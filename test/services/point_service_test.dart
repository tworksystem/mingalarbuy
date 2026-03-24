import 'dart:convert';
import 'dart:math';

import 'package:ecommerce_int2/models/point_transaction.dart';
import 'package:ecommerce_int2/services/point_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'user-123';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('PointService math helpers', () {
    test('calculatePointsFromOrder applies tier multiplier and rounds', () {
      final result = PointService.calculatePointsFromOrder(
        123.45,
        multiplier: 1.2,
      );

      // 123.45 * 1.0 * 1.2 => 148.14 -> rounds to 148
      expect(result, 148);
    });

    test('calculatePointsFromOrder handles small orders and aggressive multiplier', () {
      final result = PointService.calculatePointsFromOrder(
        9.99,
        multiplier: 1.5,
      );

      // 9.99 * 1.0 * 1.5 => 14.985 -> rounds to 15
      expect(result, 15);
    });

    test('calculatePointsFromOrder returns zero when order total is zero', () {
      expect(PointService.calculatePointsFromOrder(0, multiplier: 2.0), 0);
    });

    test('calculateMaxRedeemablePoints respects max redemption percentage and rounds up', () {
      final result = PointService.calculateMaxRedeemablePoints(123.45);
      // Max 50% of order total -> $61.725 discount -> 6172.5 points => rounds to 6173
      expect(result, 6173);
    });

    test('calculatePointsForDiscount converts dollars to points and rounds', () {
      expect(PointService.calculatePointsForDiscount(12.34), 1234);
      expect(PointService.calculatePointsForDiscount(0.015), 2); // 1.5 points -> 2 after rounding
    });

    test('calculateDiscountFromPoints converts points to dollars', () {
      expect(PointService.calculateDiscountFromPoints(250), 2.5);
      expect(PointService.calculateDiscountFromPoints(75), closeTo(0.75, 1e-9));
    });

    test('isValidRedemptionAmount enforces min, balance and cap rules', () {
      const orderTotal = 150.0;
      const currentBalance = 5000;

      expect(
        PointService.isValidRedemptionAmount(50, orderTotal, currentBalance),
        isFalse,
        reason: 'Below minimum redemption',
      );

      expect(
        PointService.isValidRedemptionAmount(6000, orderTotal, currentBalance),
        isFalse,
        reason: 'Above available balance',
      );

      final maxRedeemable =
          PointService.calculateMaxRedeemablePoints(orderTotal);
      expect(
        PointService.isValidRedemptionAmount(
          maxRedeemable + 100,
          orderTotal,
          currentBalance,
        ),
        isFalse,
        reason: 'Above 50% order total cap',
      );

      final allowedPoints = min(maxRedeemable, currentBalance);
      expect(
        PointService.isValidRedemptionAmount(
          allowedPoints,
          orderTotal,
          currentBalance,
        ),
        isTrue,
      );
    });

    test('isValidRedemptionAmount rejects redemptions when order total is zero', () {
      expect(
        PointService.isValidRedemptionAmount(
          PointService.minRedemptionPoints,
          0,
          10 * PointService.minRedemptionPoints,
        ),
        isFalse,
      );
    });
  });

  group('PointService expiration handling', () {
    test('checkAndMarkExpiredPoints creates expire transaction and adjusts balance',
        () async {
      final prefs = await SharedPreferences.getInstance();

      final balance = PointBalance(
        userId: userId,
        currentBalance: 1500,
        lifetimeEarned: 2000,
        lifetimeRedeemed: 300,
        lifetimeExpired: 200,
        lastUpdated: DateTime.now(),
      );

      final now = DateTime.now();
      final expiredTransaction = PointTransaction(
        id: 'expired-1',
        userId: userId,
        type: PointTransactionType.earn,
        points: 400,
        description: 'Promo points',
        createdAt: now.subtract(const Duration(days: 400)),
        expiresAt: now.subtract(const Duration(days: 1)),
      );

      final activeTransaction = PointTransaction(
        id: 'active-1',
        userId: userId,
        type: PointTransactionType.earn,
        points: 300,
        description: 'Recent points',
        createdAt: now.subtract(const Duration(days: 10)),
        expiresAt: now.add(const Duration(days: 100)),
      );

      await prefs.setString(
        'user_point_balance$userId',
        json.encode(balance.toJson()),
      );

      await prefs.setString(
        'user_point_transactions$userId',
        json.encode([
          expiredTransaction.toJson(),
          activeTransaction.toJson(),
        ]),
      );

      final expiredCount =
          await PointService.checkAndMarkExpiredPoints(userId);

      expect(expiredCount, 1);

      final updatedBalance = await PointService.getCachedBalance(userId);
      expect(updatedBalance, isNotNull);
      expect(updatedBalance!.currentBalance, 1100);
      expect(updatedBalance.lifetimeExpired, balance.lifetimeExpired + 400);

      final cachedTransactions =
          await PointService.getCachedTransactions(userId);
      expect(cachedTransactions.length, 3);

      final expireEntries = cachedTransactions
          .where((t) => t.type == PointTransactionType.expire)
          .toList();
      expect(expireEntries.length, 1);
      expect(expireEntries.first.points, 400);
      expect(expireEntries.first.description,
          contains('transaction'));
    });

    test('checkAndMarkExpiredPoints returns zero when nothing has expired', () async {
      final prefs = await SharedPreferences.getInstance();

      final balance = PointBalance(
        userId: userId,
        currentBalance: 800,
        lifetimeEarned: 1200,
        lifetimeRedeemed: 200,
        lifetimeExpired: 100,
        lastUpdated: DateTime.now(),
      );

      final now = DateTime.now();
      final nonExpiring = PointTransaction(
        id: 'earn-1',
        userId: userId,
        type: PointTransactionType.earn,
        points: 300,
        description: 'Welcome bonus',
        createdAt: now.subtract(const Duration(days: 5)),
        expiresAt: now.add(const Duration(days: 10)),
      );

      await prefs.setString(
        'user_point_balance$userId',
        json.encode(balance.toJson()),
      );

      await prefs.setString(
        'user_point_transactions$userId',
        json.encode([
          nonExpiring.toJson(),
        ]),
      );

      final expiredCount =
          await PointService.checkAndMarkExpiredPoints(userId);

      expect(expiredCount, 0);

      final updatedBalance = await PointService.getCachedBalance(userId);
      expect(updatedBalance, isNotNull);
      expect(updatedBalance!.currentBalance, balance.currentBalance);

      final cachedTransactions =
          await PointService.getCachedTransactions(userId);
      expect(
        cachedTransactions.where((t) => t.type == PointTransactionType.expire),
        isEmpty,
      );
    });
  });
}

