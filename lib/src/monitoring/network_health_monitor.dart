import 'dart:async';

/// Monitors network health and sync performance.
///
/// Tracks key metrics to assess the quality of the LAN synchronization:
/// - Messages sent/received counters
/// - Error tracking and categorization
/// - Latency measurements
/// - Health score calculation (0.0 - 1.0)
///
/// Example:
/// ```dart
/// final monitor = NetworkHealthMonitor();
///
/// // Record message sent
/// monitor.recordMessageSent('msg-123');
///
/// // Record message received
/// monitor.recordMessageReceived('msg-123', Duration(milliseconds: 50));
///
/// // Record error
/// monitor.recordError(NetworkError.sendFailed, 'Connection refused');
///
/// // Get health status
/// final health = monitor.getHealthScore();
/// print('Network health: ${(health * 100).toStringAsFixed(1)}%');
///
/// // Get detailed metrics
/// final metrics = monitor.getMetrics();
/// print(metrics);
/// ```
class NetworkHealthMonitor {
  /// Reset window for counters (prevents overflow)
  final Duration resetWindow;

  /// Counters
  int _messagesSent = 0;
  int _messagesReceived = 0;
  final Map<NetworkError, int> _errorCounts = {};

  /// Latency tracking (last 100 measurements)
  final List<Duration> _recentLatencies = [];
  static const _maxLatencySamples = 100;

  /// Timestamp of last reset
  DateTime _lastReset = DateTime.now();

  /// Stream controller for health alerts
  final _alertController = StreamController<HealthAlert>.broadcast();

  /// Stream of health alerts (warnings about network issues)
  Stream<HealthAlert> get alerts => _alertController.stream;

  /// Health thresholds for alerts
  double healthWarningThreshold = 0.7;
  double healthCriticalThreshold = 0.5;
  double _lastHealthScore = 1.0;

  NetworkHealthMonitor({this.resetWindow = const Duration(hours: 1)});

  /// Record that a message was sent.
  void recordMessageSent(String messageId) {
    _messagesSent++;
    _checkResetWindow();
  }

  /// Record that a message was received.
  ///
  /// Optionally provide the latency (time from send to receive).
  void recordMessageReceived(String messageId, [Duration? latency]) {
    _messagesReceived++;

    if (latency != null) {
      _recentLatencies.add(latency);

      // Keep only recent samples
      if (_recentLatencies.length > _maxLatencySamples) {
        _recentLatencies.removeAt(0);
      }
    }

    _checkResetWindow();
  }

  /// Record a network error.
  ///
  /// Errors are categorized by type and tracked separately.
  /// Optionally provide additional context for logging.
  void recordError(NetworkError error, [String? context]) {
    _errorCounts[error] = (_errorCounts[error] ?? 0) + 1;

    // Emit alert if error rate is high
    _checkErrorRate();
    _checkResetWindow();
  }

  /// Get current health metrics.
  HealthMetrics getMetrics() {
    return HealthMetrics(
      messagesSent: _messagesSent,
      messagesReceived: _messagesReceived,
      errorCounts: Map.unmodifiable(_errorCounts),
      totalErrors: _getTotalErrors(),
      averageLatency: _calculateAverageLatency(),
      packetLossRate: _calculatePacketLossRate(),
      errorRate: _calculateErrorRate(),
      healthScore: getHealthScore(),
    );
  }

  /// Get current health score (0.0 - 1.0).
  ///
  /// Health score is calculated from:
  /// - Packet loss rate (lower is better)
  /// - Error rate (lower is better)
  /// - Latency (lower is better)
  ///
  /// Score interpretation:
  /// - 0.9 - 1.0: Excellent
  /// - 0.7 - 0.9: Good
  /// - 0.5 - 0.7: Fair (warning)
  /// - 0.0 - 0.5: Poor (critical)
  double getHealthScore() {
    if (_messagesSent == 0) {
      return 1.0; // No data yet, assume healthy
    }

    // Factor 1: Delivery rate (weight: 0.5)
    final deliveryRate = _messagesReceived / _messagesSent;
    final deliveryScore = deliveryRate.clamp(0.0, 1.0);

    // Factor 2: Error rate (weight: 0.3)
    final errorRate = _calculateErrorRate();
    final errorScore = (1.0 - errorRate).clamp(0.0, 1.0);

    // Factor 3: Latency (weight: 0.2)
    final latencyScore = _calculateLatencyScore();

    // Weighted combination
    final healthScore =
        (deliveryScore * 0.5) + (errorScore * 0.3) + (latencyScore * 0.2);

    // Check for health degradation
    if (healthScore < _lastHealthScore - 0.1) {
      _emitAlert(
        HealthAlertType.degradation,
        'Network health degraded: ${(healthScore * 100).toStringAsFixed(1)}%',
      );
    }

    _lastHealthScore = healthScore;
    return healthScore.clamp(0.0, 1.0);
  }

  /// Reset all counters.
  ///
  /// Useful for testing or starting fresh measurements.
  void reset() {
    _messagesSent = 0;
    _messagesReceived = 0;
    _errorCounts.clear();
    _recentLatencies.clear();
    _lastReset = DateTime.now();
    _lastHealthScore = 1.0;
  }

  /// Clean up resources.
  void dispose() {
    _alertController.close();
  }

  /// Calculate packet loss rate (0.0 - 1.0).
  double _calculatePacketLossRate() {
    if (_messagesSent == 0) return 0.0;

    final lost = _messagesSent - _messagesReceived;
    return (lost / _messagesSent).clamp(0.0, 1.0);
  }

  /// Calculate error rate (errors per message sent).
  double _calculateErrorRate() {
    if (_messagesSent == 0) return 0.0;

    final totalErrors = _getTotalErrors();
    return (totalErrors / _messagesSent).clamp(0.0, 1.0);
  }

  /// Calculate latency score (0.0 - 1.0, higher is better).
  double _calculateLatencyScore() {
    if (_recentLatencies.isEmpty) return 1.0;

    final avgLatency = _calculateAverageLatency();

    // Score based on latency ranges:
    // < 10ms: excellent (1.0)
    // < 50ms: good (0.8)
    // < 100ms: fair (0.6)
    // < 500ms: poor (0.3)
    // > 500ms: very poor (0.1)

    if (avgLatency.inMilliseconds < 10) return 1.0;
    if (avgLatency.inMilliseconds < 50) return 0.8;
    if (avgLatency.inMilliseconds < 100) return 0.6;
    if (avgLatency.inMilliseconds < 500) return 0.3;
    return 0.1;
  }

  /// Calculate average latency from recent samples.
  Duration _calculateAverageLatency() {
    if (_recentLatencies.isEmpty) return Duration.zero;

    final totalMs = _recentLatencies.fold<int>(
      0,
      (sum, latency) => sum + latency.inMilliseconds,
    );

    return Duration(milliseconds: totalMs ~/ _recentLatencies.length);
  }

  /// Get total error count across all types.
  int _getTotalErrors() {
    return _errorCounts.values.fold(0, (sum, count) => sum + count);
  }

  /// Check if counters should be reset to prevent overflow.
  void _checkResetWindow() {
    final now = DateTime.now();
    if (now.difference(_lastReset) > resetWindow) {
      // Soft reset: keep recent latencies, scale down counters
      _messagesSent = (_messagesSent * 0.1).round();
      _messagesReceived = (_messagesReceived * 0.1).round();

      _errorCounts.updateAll((key, value) => (value * 0.1).round());

      _lastReset = now;
    }
  }

  /// Check error rate and emit alert if too high.
  void _checkErrorRate() {
    final errorRate = _calculateErrorRate();

    if (errorRate > 0.1) {
      // More than 10% errors
      _emitAlert(
        HealthAlertType.highErrorRate,
        'High error rate: ${(errorRate * 100).toStringAsFixed(1)}%',
      );
    }
  }

  /// Emit a health alert.
  void _emitAlert(HealthAlertType type, String message) {
    _alertController.add(
      HealthAlert(type: type, message: message, timestamp: DateTime.now()),
    );
  }
}

/// Network health metrics snapshot.
class HealthMetrics {
  final int messagesSent;
  final int messagesReceived;
  final Map<NetworkError, int> errorCounts;
  final int totalErrors;
  final Duration averageLatency;
  final double packetLossRate;
  final double errorRate;
  final double healthScore;

  const HealthMetrics({
    required this.messagesSent,
    required this.messagesReceived,
    required this.errorCounts,
    required this.totalErrors,
    required this.averageLatency,
    required this.packetLossRate,
    required this.errorRate,
    required this.healthScore,
  });

  @override
  String toString() {
    return '''
HealthMetrics:
  Messages: $messagesReceived / $messagesSent (${(packetLossRate * 100).toStringAsFixed(1)}% loss)
  Errors: $totalErrors (${(errorRate * 100).toStringAsFixed(1)}% error rate)
  Latency: ${averageLatency.inMilliseconds}ms avg
  Health Score: ${(healthScore * 100).toStringAsFixed(1)}%
  
Error Breakdown:
${errorCounts.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}
''';
  }
}

/// Types of network errors that can occur.
enum NetworkError {
  /// Failed to send message
  sendFailed,

  /// Failed to receive message
  receiveFailed,

  /// Message timeout (no response)
  timeout,

  /// Checksum mismatch
  checksumMismatch,

  /// Invalid message format
  invalidMessage,

  /// Connection lost
  connectionLost,
}

/// Types of health alerts.
enum HealthAlertType {
  /// Network health has degraded significantly
  degradation,

  /// Error rate is too high
  highErrorRate,

  /// Packet loss is too high
  highPacketLoss,

  /// Latency is too high
  highLatency,
}

/// Health alert notification.
class HealthAlert {
  final HealthAlertType type;
  final String message;
  final DateTime timestamp;

  const HealthAlert({
    required this.type,
    required this.message,
    required this.timestamp,
  });

  @override
  String toString() {
    return '[${timestamp.toIso8601String()}] $type: $message';
  }
}
