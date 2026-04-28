import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PointsDashboardCard extends StatefulWidget {
  const PointsDashboardCard({super.key});

  @override
  State<PointsDashboardCard> createState() => _PointsDashboardCardState();
}

class _PointsDashboardCardState extends State<PointsDashboardCard> {
  bool _requestedSummary = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedSummary) return;

    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated || authProvider.user == null) return;

    _requestedSummary = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<PointProvider>()
          .loadProfileHistorySummary(authProvider.user!.id.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PointProvider>(
      builder: (context, pointProvider, child) {
        final balance = pointProvider.balance;
        final summary = pointProvider.historySummary;
        final error = pointProvider.errorMessage;
        final currentBalance = balance?.currentBalance ?? 0;
        final monthlyAdded = summary?.totalAdded ?? 0;
        final monthlyDeducted = summary?.totalDeducted ?? 0;

        if (pointProvider.isLoading && balance == null && summary == null) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }

        if (balance == null && summary == null) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error != null && error.trim().isNotEmpty
                        ? 'Could not load monthly summary right now.'
                        : 'Monthly summary will appear after transactions are loaded.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1E3A8A),
                const Color(0xFF2563EB),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.dashboard_customize_outlined,
                      color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'PNP Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'လက်ရှိ Balance',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$currentBalance PNP',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: 'ဒီလအတွင်း အဝင်',
                      value: '+$monthlyAdded',
                      valueColor: Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'ဒီလအတွင်း အထွက်',
                      value: '-$monthlyDeducted',
                      valueColor: const Color(0xFFFCA5A5),
                    ),
                  ),
                ],
              ),
              if (summary != null) ...[
                const SizedBox(height: 12),
                Text(
                  'This month overview',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$value PNP',
            style: TextStyle(
              color: valueColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
