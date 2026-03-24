import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_int2/utils/monitoring.dart';

void main() {
  group('MonitoringService Tests', () {
    setUp(() async {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
      await MonitoringService.dispose();
    });

    tearDown(() async {
      await MonitoringService.dispose();
    });

    group('Initialization', () {
      test('should initialize successfully', () async {
        await MonitoringService.initialize();
        expect(MonitoringService, isNotNull);
      });

      test('should not initialize twice', () async {
        await MonitoringService.initialize();
        await MonitoringService.initialize(); // Should not throw
        expect(MonitoringService, isNotNull);
      });

      test('should dispose properly', () async {
        await MonitoringService.initialize();
        await MonitoringService.dispose();
        // Should not throw when called again
        await MonitoringService.dispose();
      });
    });

    group('Metrics Tracking', () {
      test('should track metric successfully', () async {
        await MonitoringService.initialize();

        await MonitoringService.trackMetric('test_metric', 42.0,
            tags: {'test': 'value'});

        final metrics = await MonitoringService.exportMetrics();
        expect(metrics['metrics'], isNotEmpty);
        expect(metrics['metrics']['test_metric'], isNotNull);
        expect(metrics['metrics']['test_metric']['value'], equals(42.0));
      });

      test('should handle metric tracking errors gracefully', () async {
        await MonitoringService.initialize();

        // Should not throw even with invalid data
        await MonitoringService.trackMetric('', double.nan);
        await MonitoringService.trackMetric('test', double.infinity);
      });
    });

    group('Performance Events', () {
      test('should track performance event', () async {
        await MonitoringService.initialize();

        await MonitoringService.trackPerformanceEvent(
          'test_operation',
          const Duration(milliseconds: 100),
          metadata: {'test': 'data'},
          userId: 'user123',
        );

        final summary = await MonitoringService.getPerformanceSummary();
        expect(summary.totalEvents, equals(1));
        expect(summary.averageResponseTime, equals(100.0));
      });

      test('should track operation timing', () async {
        await MonitoringService.initialize();

        MonitoringService.startOperation('test_op');
        await Future.delayed(const Duration(milliseconds: 50));
        await MonitoringService.endOperation('test_op');

        final summary = await MonitoringService.getPerformanceSummary();
        expect(summary.totalEvents, equals(1));
        expect(summary.averageResponseTime, greaterThan(40));
        expect(summary.averageResponseTime, lessThan(100));
      });
    });

    group('Error Events', () {
      test('should track error event', () async {
        await MonitoringService.initialize();

        await MonitoringService.trackErrorEvent(
          'test_operation',
          'Test error',
          stackTrace: StackTrace.current,
          metadata: {'context': 'test'},
          userId: 'user123',
          severity: 'error',
        );

        final summary = await MonitoringService.getPerformanceSummary();
        expect(summary.totalErrors, equals(1));
        expect(summary.errorRate, equals(1.0));
      });

      test('should handle null severity gracefully', () async {
        await MonitoringService.initialize();

        await MonitoringService.trackErrorEvent(
          'test_operation',
          'Test error',
          severity: null,
        );

        final summary = await MonitoringService.getPerformanceSummary();
        expect(summary.totalErrors, equals(1));
      });
    });

    group('Business Events', () {
      test('should track business event', () async {
        await MonitoringService.initialize();

        await MonitoringService.trackBusinessEvent(
          'test_event',
          data: {'value': 123},
          userId: 'user123',
          sessionId: 'session456',
        );

        final metrics = await MonitoringService.exportMetrics();
        expect(metrics['business_events'], isNotEmpty);
        expect(
            metrics['business_events'][0]['event_type'], equals('test_event'));
      });

      test('should track order creation', () async {
        await MonitoringService.initialize();

        await MonitoringService.trackOrderCreation(
          'order123',
          total: 99.99,
          itemCount: 3,
          paymentMethod: 'credit_card',
          userId: 'user123',
        );

        final businessMetrics = await MonitoringService.getBusinessMetrics();
        expect(businessMetrics.totalOrders, equals(1));
        expect(businessMetrics.totalRevenue, equals(99.99));
        expect(businessMetrics.averageOrderValue, equals(99.99));
      });

      test('should track order status change', () async {
        await MonitoringService.initialize();

        await MonitoringService.trackOrderStatusChange(
          'order123',
          'pending',
          'processing',
          userId: 'user123',
          timeInStatus: const Duration(minutes: 5),
        );

        final metrics = await MonitoringService.exportMetrics();
        final businessEvents = metrics['business_events'] as List;
        final statusChangeEvent = businessEvents.firstWhere(
          (event) => event['event_type'] == 'order_status_changed',
        );
        expect(statusChangeEvent['data']['old_status'], equals('pending'));
        expect(statusChangeEvent['data']['new_status'], equals('processing'));
      });
    });

    group('API Tracking', () {
      test('should track API request and response', () async {
        await MonitoringService.initialize();

        await MonitoringService.trackApiRequest(
          'GET',
          'https://api.example.com/users',
          headers: {'Authorization': 'Bearer token'},
          body: '{"test": "data"}',
          userId: 'user123',
        );

        await MonitoringService.trackApiResponse(
          'GET',
          'https://api.example.com/users',
          200,
          duration: const Duration(milliseconds: 150),
          userId: 'user123',
        );

        final summary = await MonitoringService.getPerformanceSummary();
        expect(summary.totalEvents, equals(1));
        expect(summary.averageResponseTime, equals(150.0));
      });
    });

    group('Health Checks', () {
      test('should add and perform health check', () async {
        await MonitoringService.initialize();

        bool isHealthy = true;
        await MonitoringService.addHealthCheck(
            'test_service', () async => isHealthy);

        var healthStatus = await MonitoringService.getHealthStatus();
        expect(healthStatus['test_service'], isFalse); // Not checked yet

        // Simulate health check
        isHealthy = false;
        await MonitoringService.addHealthCheck(
            'test_service', () async => isHealthy);

        healthStatus = await MonitoringService.getHealthStatus();
        expect(healthStatus['test_service'], isFalse);
      });
    });

    group('Data Persistence', () {
      test('should persist and load data', () async {
        await MonitoringService.initialize(enablePersistence: true);

        await MonitoringService.trackMetric('persistent_metric', 42.0);
        await MonitoringService.trackBusinessEvent('persistent_event');

        // Simulate app restart by disposing and reinitializing
        await MonitoringService.dispose();
        await MonitoringService.initialize(enablePersistence: true);

        final metrics = await MonitoringService.exportMetrics();
        expect(metrics['metrics']['persistent_metric'], isNotNull);
        expect(metrics['business_events'], isNotEmpty);
      });
    });

    group('Performance Summary', () {
      test('should calculate performance summary correctly', () async {
        await MonitoringService.initialize();

        // Add some performance events
        await MonitoringService.trackPerformanceEvent(
            'op1', const Duration(milliseconds: 100));
        await MonitoringService.trackPerformanceEvent(
            'op1', const Duration(milliseconds: 200));
        await MonitoringService.trackPerformanceEvent(
            'op2', const Duration(milliseconds: 150));

        // Add some errors
        await MonitoringService.trackErrorEvent('op1', 'Error 1');
        await MonitoringService.trackErrorEvent('op2', 'Error 2');

        final summary = await MonitoringService.getPerformanceSummary();
        expect(summary.totalEvents, equals(3));
        expect(summary.totalErrors, equals(2));
        expect(summary.averageResponseTime, equals(150.0));
        expect(summary.errorRate, closeTo(0.67, 0.01));
        expect(summary.topOperations.length, equals(2));
      });

      test('should handle empty performance data', () async {
        await MonitoringService.initialize();

        final summary = await MonitoringService.getPerformanceSummary();
        expect(summary.totalEvents, equals(0));
        expect(summary.totalErrors, equals(0));
        expect(summary.averageResponseTime, equals(0.0));
        expect(summary.errorRate, equals(0.0));
      });
    });

    group('Business Metrics', () {
      test('should calculate business metrics correctly', () async {
        await MonitoringService.initialize();

        // Create some orders
        await MonitoringService.trackOrderCreation('order1',
            total: 100.0, itemCount: 2, paymentMethod: 'credit_card');
        await MonitoringService.trackOrderCreation('order2',
            total: 200.0, itemCount: 1, paymentMethod: 'paypal');
        await MonitoringService.trackOrderCreation('order3',
            total: 150.0, itemCount: 3, paymentMethod: 'credit_card');

        final metrics = await MonitoringService.getBusinessMetrics();
        expect(metrics.totalOrders, equals(3));
        expect(metrics.totalRevenue, equals(450.0));
        expect(metrics.averageOrderValue, equals(150.0));
        expect(metrics.topPaymentMethods.length, equals(2));
        expect(metrics.topPaymentMethods[0].method, equals('credit_card'));
        expect(metrics.topPaymentMethods[0].count, equals(2));
      });

      test('should handle empty business data', () async {
        await MonitoringService.initialize();

        final metrics = await MonitoringService.getBusinessMetrics();
        expect(metrics.totalOrders, equals(0));
        expect(metrics.totalRevenue, equals(0.0));
        expect(metrics.averageOrderValue, equals(0.0));
      });
    });

    group('Circuit Breaker', () {
      test('should implement circuit breaker pattern', () async {
        await MonitoringService.initialize();

        // Test API tracking with circuit breaker
        await MonitoringService.trackApiRequest(
            'GET', 'https://api.example.com/test');
        await MonitoringService.trackApiResponse(
            'GET', 'https://api.example.com/test', 200);

        final metrics = await MonitoringService.exportMetrics();
        expect(metrics['circuit_breakers'], isNotNull);
      });
    });

    group('Error Handling', () {
      test('should handle disposal gracefully', () async {
        await MonitoringService.initialize();
        await MonitoringService.dispose();

        // Should not throw when trying to track after disposal
        await MonitoringService.trackMetric('test', 1.0);
        await MonitoringService.trackPerformanceEvent(
            'test', const Duration(seconds: 1));
        await MonitoringService.trackErrorEvent('test', 'error');
        await MonitoringService.trackBusinessEvent('test');
      });

      test('should handle concurrent access', () async {
        await MonitoringService.initialize();

        // Simulate concurrent access with fewer operations to avoid memory issues
        final futures = <Future>[];
        for (int i = 0; i < 5; i++) {
          futures.add(MonitoringService.trackMetric('metric_$i', i.toDouble()));
          futures.add(MonitoringService.trackPerformanceEvent(
              'op_$i', Duration(milliseconds: i * 10)));
          futures.add(MonitoringService.trackBusinessEvent('event_$i'));
        }

        await Future.wait(futures);

        final summary = await MonitoringService.getPerformanceSummary();
        expect(summary.totalEvents, equals(5));
      });
    });

    group('Memory Management', () {
      test('should enforce event limits', () async {
        await MonitoringService.initialize();

        // Add more events than the limit
        for (int i = 0; i < 10001; i++) {
          await MonitoringService.trackPerformanceEvent(
              'op_$i', const Duration(milliseconds: 1));
        }

        final summary = await MonitoringService.getPerformanceSummary();
        expect(summary.totalEvents, lessThanOrEqualTo(10000));
      });
    });

    group('Export Functionality', () {
      test('should export comprehensive metrics', () async {
        await MonitoringService.initialize();

        // Add various types of data
        await MonitoringService.trackMetric('test_metric', 42.0);
        await MonitoringService.trackPerformanceEvent(
            'test_op', const Duration(milliseconds: 100));
        await MonitoringService.trackErrorEvent('test_op', 'test error');
        await MonitoringService.trackBusinessEvent('test_event');

        final export = await MonitoringService.exportMetrics();

        expect(export, containsPair('metrics', isA<Map>()));
        expect(export, containsPair('performance_events', isA<List>()));
        expect(export, containsPair('error_events', isA<List>()));
        expect(export, containsPair('business_events', isA<List>()));
        expect(export, containsPair('summary', isA<Map>()));
        expect(export, containsPair('business_metrics', isA<Map>()));
        expect(export, containsPair('export_timestamp', isA<String>()));
      });
    });
  });

  group('Data Classes Tests', () {
    test('Metric serialization', () {
      final metric = Metric(
        name: 'test_metric',
        value: 42.0,
        timestamp: DateTime.now(),
        tags: {'test': 'value'},
      );

      final json = metric.toJson();
      expect(json['name'], equals('test_metric'));
      expect(json['value'], equals(42.0));
      expect(json['tags']['test'], equals('value'));

      final restored = Metric.fromJson(json);
      expect(restored.name, equals(metric.name));
      expect(restored.value, equals(metric.value));
      expect(restored.tags, equals(metric.tags));
    });

    test('PerformanceEvent serialization', () {
      final event = PerformanceEvent(
        operation: 'test_op',
        duration: const Duration(milliseconds: 100),
        timestamp: DateTime.now(),
        metadata: {'test': 'data'},
        userId: 'user123',
      );

      final json = event.toJson();
      expect(json['operation'], equals('test_op'));
      expect(json['duration_ms'], equals(100));
      expect(json['metadata']['test'], equals('data'));
      expect(json['user_id'], equals('user123'));
    });

    test('ErrorEvent serialization', () {
      final event = ErrorEvent(
        operation: 'test_op',
        error: 'test error',
        stackTrace: 'test stack trace',
        timestamp: DateTime.now(),
        metadata: {'test': 'data'},
        userId: 'user123',
        severity: 'error',
      );

      final json = event.toJson();
      expect(json['operation'], equals('test_op'));
      expect(json['error'], equals('test error'));
      expect(json['severity'], equals('error'));
    });

    test('BusinessEvent serialization', () {
      final event = BusinessEvent(
        eventType: 'test_event',
        data: {'value': 123},
        timestamp: DateTime.now(),
        userId: 'user123',
        sessionId: 'session456',
      );

      final json = event.toJson();
      expect(json['event_type'], equals('test_event'));
      expect(json['data']['value'], equals(123));
      expect(json['user_id'], equals('user123'));
      expect(json['session_id'], equals('session456'));
    });
  });
}
