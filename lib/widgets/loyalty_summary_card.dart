import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Profile summary for PNP balance (tier system removed; backend no longer exposes tiers).
class LoyaltySummaryCard extends StatelessWidget {
  const LoyaltySummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PointProvider>(
      builder: (context, pointProvider, child) {
        final balance = pointProvider.balance;
        if (balance == null) {
          return const SizedBox.shrink();
        }

        final earned = balance.lifetimeEarned;
        final current = balance.currentBalance;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.deepPurple.shade400,
                Colors.indigo.shade500,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars_rounded, color: Colors.amberAccent, size: 28),
                  const SizedBox(width: 8),
                  const Text(
                    'Rewards balance',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$current PNP',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                earned > 0
                    ? 'Lifetime earned: $earned PNP'
                    : 'Earn PNP on purchases and activities.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
