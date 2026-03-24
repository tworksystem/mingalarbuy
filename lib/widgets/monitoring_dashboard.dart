import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../utils/monitoring.dart';
import '../utils/logger.dart';

/// Enterprise-grade monitoring dashboard widget
class MonitoringDashboard extends StatefulWidget {
  final bool showRealTimeMetrics;
  final Duration refreshInterval;
  final bool enableExport;
  final VoidCallback? onClose;

  const MonitoringDashboard({
    super.key,
    this.showRealTimeMetrics = true,
    // OPTIMIZED: Increased from 5s to 15s to reduce CPU usage
    this.refreshInterval = const Duration(seconds: 15),
    this.enableExport = true,
    this.onClose,
  });

  @override
  State<MonitoringDashboard> createState() => _MonitoringDashboardState();
}

class _MonitoringDashboardState extends State<MonitoringDashboard>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  PerformanceSummary? _performanceSummary;
  BusinessMetrics? _businessMetrics;
  Map<String, bool> _healthStatus = {};
  Map<String, dynamic> _exportedMetrics = {};

  bool _isLoading = false;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.forward();
    _loadMetrics();

    if (widget.showRealTimeMetrics) {
      _refreshTimer =
          Timer.periodic(widget.refreshInterval, (_) => _loadMetrics());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final performanceSummary =
          await MonitoringService.getPerformanceSummary();
      final businessMetrics = await MonitoringService.getBusinessMetrics();
      final healthStatus = await MonitoringService.getHealthStatus();
      final exportedMetrics = await MonitoringService.exportMetrics();

      if (mounted) {
        setState(() {
          _performanceSummary = performanceSummary;
          _businessMetrics = businessMetrics;
          _healthStatus = healthStatus;
          _exportedMetrics = exportedMetrics;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      Logger.error('Failed to load monitoring metrics',
          tag: 'MonitoringDashboard', error: e, stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _exportMetrics() async {
    try {
      final metrics = await MonitoringService.exportMetrics();
      final jsonString = const JsonEncoder.withIndent('  ').convert(metrics);

      if (kDebugMode) {
        Logger.info('Exported metrics: $jsonString',
            tag: 'MonitoringDashboard');
      }

      // In a real app, you might want to save to file or send to server
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Metrics exported successfully')),
      );
    } catch (e, stackTrace) {
      Logger.error('Failed to export metrics',
          tag: 'MonitoringDashboard', error: e, stackTrace: stackTrace);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export metrics: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Scaffold(
        backgroundColor: Colors.grey[900],
        appBar: AppBar(
          title: const Text('Monitoring Dashboard'),
          backgroundColor: Colors.grey[800],
          foregroundColor: Colors.white,
          actions: [
            if (widget.enableExport)
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: _exportMetrics,
                tooltip: 'Export Metrics',
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadMetrics,
              tooltip: 'Refresh',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onClose,
              tooltip: 'Close',
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blue),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              'Failed to load metrics',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[400],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMetrics,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPerformanceSection(),
          const SizedBox(height: 24),
          _buildBusinessSection(),
          const SizedBox(height: 24),
          _buildHealthSection(),
          const SizedBox(height: 24),
          _buildSystemSection(),
        ],
      ),
    );
  }

  Widget _buildPerformanceSection() {
    if (_performanceSummary == null) return const SizedBox.shrink();

    return _buildSection(
      title: 'Performance Metrics',
      icon: Icons.speed,
      color: Colors.blue,
      children: [
        _buildMetricCard(
          'Total Events',
          _performanceSummary!.totalEvents.toString(),
          Icons.analytics,
          Colors.blue,
        ),
        _buildMetricCard(
          'Total Errors',
          _performanceSummary!.totalErrors.toString(),
          Icons.error,
          Colors.red,
        ),
        _buildMetricCard(
          'Average Response Time',
          '${_performanceSummary!.averageResponseTime.toStringAsFixed(2)}ms',
          Icons.timer,
          Colors.orange,
        ),
        _buildMetricCard(
          'Error Rate',
          '${(_performanceSummary!.errorRate * 100).toStringAsFixed(2)}%',
          Icons.trending_down,
          _performanceSummary!.errorRate > 0.1 ? Colors.red : Colors.green,
        ),
        _buildMetricCard(
          'P95 Response Time',
          '${_performanceSummary!.p95ResponseTime.toStringAsFixed(2)}ms',
          Icons.timeline,
          Colors.purple,
        ),
        _buildMetricCard(
          'P99 Response Time',
          '${_performanceSummary!.p99ResponseTime.toStringAsFixed(2)}ms',
          Icons.timeline,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildBusinessSection() {
    if (_businessMetrics == null) return const SizedBox.shrink();

    return _buildSection(
      title: 'Business Metrics',
      icon: Icons.business,
      color: Colors.green,
      children: [
        _buildMetricCard(
          'Total Orders',
          _businessMetrics!.totalOrders.toString(),
          Icons.shopping_cart,
          Colors.green,
        ),
        _buildMetricCard(
          'Total Revenue',
          '${_businessMetrics!.totalRevenue.toStringAsFixed(2)} Ks',
          Icons.attach_money,
          Colors.green,
        ),
        _buildMetricCard(
          'Average Order Value',
          '${_businessMetrics!.averageOrderValue.toStringAsFixed(2)} Ks',
          Icons.trending_up,
          Colors.blue,
        ),
        _buildMetricCard(
          'Conversion Rate',
          '${(_businessMetrics!.conversionRate * 100).toStringAsFixed(2)}%',
          Icons.trending_up,
          Colors.orange,
        ),
        _buildMetricCard(
          'Retention Rate',
          '${(_businessMetrics!.customerRetentionRate * 100).toStringAsFixed(2)}%',
          Icons.people,
          Colors.purple,
        ),
        if (_businessMetrics!.topPaymentMethods.isNotEmpty)
          _buildPaymentMethodsCard(),
      ],
    );
  }

  Widget _buildHealthSection() {
    return _buildSection(
      title: 'Health Status',
      icon: Icons.health_and_safety,
      color: Colors.orange,
      children: [
        if (_healthStatus.isEmpty)
          _buildMetricCard(
            'No Health Checks',
            'No health checks configured',
            Icons.info,
            Colors.grey,
          )
        else
          ..._healthStatus.entries.map((entry) => _buildMetricCard(
                entry.key,
                entry.value ? 'Healthy' : 'Unhealthy',
                entry.value ? Icons.check_circle : Icons.error,
                entry.value ? Colors.green : Colors.red,
              )),
      ],
    );
  }

  Widget _buildSystemSection() {
    return _buildSection(
      title: 'System Information',
      icon: Icons.info,
      color: Colors.grey,
      children: [
        _buildMetricCard(
          'Export Timestamp',
          _exportedMetrics['export_timestamp']?.toString() ?? 'N/A',
          Icons.access_time,
          Colors.grey,
        ),
        _buildMetricCard(
          'Performance Events',
          (_exportedMetrics['performance_events'] as List?)
                  ?.length
                  .toString() ??
              '0',
          Icons.analytics,
          Colors.blue,
        ),
        _buildMetricCard(
          'Error Events',
          (_exportedMetrics['error_events'] as List?)?.length.toString() ?? '0',
          Icons.error,
          Colors.red,
        ),
        _buildMetricCard(
          'Business Events',
          (_exportedMetrics['business_events'] as List?)?.length.toString() ??
              '0',
          Icons.business,
          Colors.green,
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: children,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[300],
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payment, color: Colors.green, size: 16),
              const SizedBox(width: 4),
              Text(
                'Top Payment Methods',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[300],
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._businessMetrics!.topPaymentMethods.take(3).map((method) =>
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      method.method,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                    Text(
                      '${method.count}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// Compact monitoring widget for embedding in other screens
class CompactMonitoringWidget extends StatefulWidget {
  final bool showPerformance;
  final bool showBusiness;
  final bool showHealth;
  final Duration refreshInterval;

  const CompactMonitoringWidget({
    super.key,
    this.showPerformance = true,
    this.showBusiness = true,
    this.showHealth = true,
    // OPTIMIZED: Increased from 10s to 20s to reduce CPU usage
    this.refreshInterval = const Duration(seconds: 20),
  });

  @override
  State<CompactMonitoringWidget> createState() =>
      _CompactMonitoringWidgetState();
}

class _CompactMonitoringWidgetState extends State<CompactMonitoringWidget> {
  PerformanceSummary? _performanceSummary;
  BusinessMetrics? _businessMetrics;
  Map<String, bool> _healthStatus = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
    _refreshTimer =
        Timer.periodic(widget.refreshInterval, (_) => _loadMetrics());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    if (!mounted) return;

    try {
      final performanceSummary =
          await MonitoringService.getPerformanceSummary();
      final businessMetrics = await MonitoringService.getBusinessMetrics();
      final healthStatus = await MonitoringService.getHealthStatus();

      if (mounted) {
        setState(() {
          _performanceSummary = performanceSummary;
          _businessMetrics = businessMetrics;
          _healthStatus = healthStatus;
        });
      }
    } catch (e) {
      Logger.error('Failed to load compact monitoring metrics',
          tag: 'CompactMonitoringWidget', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'System Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _loadMetrics,
                  child:
                      const Icon(Icons.refresh, color: Colors.grey, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.showPerformance && _performanceSummary != null)
              _buildCompactMetric(
                  'Events', _performanceSummary!.totalEvents.toString()),
            if (widget.showPerformance && _performanceSummary != null)
              _buildCompactMetric(
                  'Errors', _performanceSummary!.totalErrors.toString()),
            if (widget.showBusiness && _businessMetrics != null)
              _buildCompactMetric(
                  'Orders', _businessMetrics!.totalOrders.toString()),
            if (widget.showBusiness && _businessMetrics != null)
              _buildCompactMetric('Revenue',
                  '${_businessMetrics!.totalRevenue.toStringAsFixed(0)} Ks'),
            if (widget.showHealth && _healthStatus.isNotEmpty)
              _buildCompactMetric('Health',
                  _healthStatus.values.every((h) => h) ? 'OK' : 'Issues'),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[300],
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
