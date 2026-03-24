import 'package:ecommerce_int2/models/point_transaction.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const Map<PointTier, List<String>> _tierBenefits = {
  PointTier.basic: [
    'Earn 1x points on every order',
    'Birthday surprise bonus',
  ],
  PointTier.bronze: [
    'Earn 1.1x points per purchase',
    'Priority customer support lane',
  ],
  PointTier.silver: [
    'Earn 1.2x points per purchase',
    'Exclusive previews and drops',
  ],
  PointTier.gold: [
    'Earn 1.3x points per purchase',
    'Complimentary expedited shipping',
  ],
  PointTier.platinum: [
    'Earn 1.5x points per purchase',
    'Dedicated loyalty concierge',
  ],
};

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

        final currentTier = balance.tier;
        final tiers = PointTier.values;
        final tierIndex = tiers.indexOf(currentTier);
        final nextTier =
            tierIndex < tiers.length - 1 ? tiers[tierIndex + 1] : null;

        final lifetimeEarned = balance.lifetimeEarned.toDouble();
        final nextThreshold =
            nextTier?.minimumPoints.toDouble() ?? lifetimeEarned;
        final progress = nextTier == null
            ? 1.0
            : (lifetimeEarned / nextThreshold).clamp(0.0, 1.0);
        final remaining =
            nextTier == null ? 0 : (nextThreshold - lifetimeEarned).ceil();

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
                color: Colors.deepPurple.withOpacity(0.25),
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
                  Text(
                    balance.tier.icon,
                    style: const TextStyle(fontSize: 28),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${balance.tier.name} Tier',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: progress,
                  backgroundColor: Colors.white.withOpacity(0.15),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                nextTier == null
                    ? 'You unlocked the highest tier!'
                    : 'Only $remaining points until you reach ${nextTier.name} tier.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Benefits',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...?_tierBenefits[currentTier]?.map(
                (benefit) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          benefit,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

