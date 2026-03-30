import 'dart:async';

/// Token bucket rate limiter to prevent network flooding.
///
/// Controls the rate at which messages can be sent using the token bucket
/// algorithm. Tokens are refilled at a constant rate, and each message
/// consumes one token. If no tokens are available, the message is blocked.
///
/// Features:
/// - Configurable rate (messages per second)
/// - Burst allowance (bucket size)
/// - Automatic token refill
/// - Metrics tracking
///
/// Example:
/// ```dart
/// // Allow 100 messages/second with burst of 10
/// final limiter = RateLimiter(
///   messagesPerSecond: 100,
///   burstSize: 10,
/// );
///
/// // Check if message can be sent
/// if (limiter.allowMessage()) {
///   // Send message...
/// } else {
///   print('Rate limit exceeded, message blocked');
/// }
///
/// // Get metrics
/// final metrics = limiter.getMetrics();
/// print('Current rate: ${metrics.currentRate} msgs/sec');
/// ```
class RateLimiter {
  /// Maximum messages per second allowed
  final int messagesPerSecond;

  /// Maximum burst size (bucket capacity)
  final int burstSize;

  /// Current number of available tokens
  double _tokens;

  /// Last time tokens were refilled
  DateTime _lastRefill;

  /// Total tokens consumed (for metrics)
  int _tokensConsumed = 0;

  /// Total messages blocked (for metrics)
  int _messagesBlocked = 0;

  /// Timer for automatic token refill
  Timer? _refillTimer;

  /// Window for rate calculation (1 second)
  static const _rateWindow = Duration(seconds: 1);

  /// Tokens consumed in current window
  final List<_TokenEvent> _recentEvents = [];

  RateLimiter({required this.messagesPerSecond, required this.burstSize})
    : _tokens = burstSize.toDouble(),
      _lastRefill = DateTime.now() {
    if (messagesPerSecond <= 0) {
      throw ArgumentError('messagesPerSecond must be positive');
    }
    if (burstSize <= 0) {
      throw ArgumentError('burstSize must be positive');
    }

    // Start automatic token refill
    _startRefillTimer();
  }

  /// Check if a message can be sent (consumes a token if available).
  ///
  /// Returns true if message is allowed (token consumed).
  /// Returns false if rate limit exceeded (no token available).
  ///
  /// This method both checks AND consumes a token in one atomic operation.
  bool allowMessage() {
    _refillTokens();

    if (_tokens >= 1.0) {
      _consumeToken();
      return true;
    } else {
      _messagesBlocked++;
      return false;
    }
  }

  /// Check if a message can be sent without consuming a token.
  ///
  /// Useful for checking rate limit status without actually sending.
  bool canSendMessage() {
    _refillTokens();
    return _tokens >= 1.0;
  }

  /// Force consume a token (for manual tracking).
  ///
  /// Returns true if token was consumed, false if no tokens available.
  ///
  /// Note: [allowMessage] is preferred as it checks and consumes atomically.
  bool consumeToken() {
    _refillTokens();

    if (_tokens >= 1.0) {
      _consumeToken();
      return true;
    }
    return false;
  }

  /// Get current rate limiter metrics.
  RateLimitMetrics getMetrics() {
    _refillTokens();
    _cleanOldEvents();

    return RateLimitMetrics(
      tokensAvailable: _tokens.floor(),
      tokensConsumed: _tokensConsumed,
      messagesBlocked: _messagesBlocked,
      currentRate: _calculateCurrentRate(),
      maxRate: messagesPerSecond,
      burstCapacity: burstSize,
    );
  }

  /// Reset all counters (for testing or reinitializing).
  void reset() {
    _tokens = burstSize.toDouble();
    _lastRefill = DateTime.now();
    _tokensConsumed = 0;
    _messagesBlocked = 0;
    _recentEvents.clear();
  }

  /// Clean up resources.
  ///
  /// Call this when the rate limiter is no longer needed to stop timers.
  void dispose() {
    _refillTimer?.cancel();
    _refillTimer = null;
    _recentEvents.clear();
  }

  /// Refill tokens based on time elapsed.
  void _refillTokens() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill);

    if (elapsed.inMilliseconds <= 0) {
      return; // No time elapsed
    }

    // Calculate tokens to add based on rate
    // Rate is messagesPerSecond, so tokens per millisecond = rate / 1000
    final tokensToAdd = (elapsed.inMilliseconds * messagesPerSecond) / 1000.0;

    // Add tokens up to burst size (cap at maximum)
    _tokens = (_tokens + tokensToAdd).clamp(0.0, burstSize.toDouble());
    _lastRefill = now;
  }

  /// Consume one token.
  void _consumeToken() {
    _tokens -= 1.0;
    _tokensConsumed++;

    // Track for rate calculation
    _recentEvents.add(_TokenEvent(timestamp: DateTime.now()));
  }

  /// Calculate current messages per second based on recent activity.
  double _calculateCurrentRate() {
    if (_recentEvents.isEmpty) {
      return 0.0;
    }

    final now = DateTime.now();
    final windowStart = now.subtract(_rateWindow);

    // Count events in the last second
    final recentCount = _recentEvents.where((event) {
      return event.timestamp.isAfter(windowStart);
    }).length;

    return recentCount.toDouble();
  }

  /// Remove events older than rate window.
  void _cleanOldEvents() {
    final now = DateTime.now();
    final windowStart = now.subtract(_rateWindow);

    _recentEvents.removeWhere((event) {
      return event.timestamp.isBefore(windowStart);
    });
  }

  /// Start automatic token refill timer.
  void _startRefillTimer() {
    // Refill every 10ms for smooth token generation
    _refillTimer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => _refillTokens(),
    );
  }
}

/// Metrics about rate limiter performance.
class RateLimitMetrics {
  /// Number of tokens currently available
  final int tokensAvailable;

  /// Total number of tokens consumed since creation/reset
  final int tokensConsumed;

  /// Total number of messages blocked due to rate limit
  final int messagesBlocked;

  /// Current rate (messages per second) based on recent activity
  final double currentRate;

  /// Maximum allowed rate (messages per second)
  final int maxRate;

  /// Maximum burst capacity (tokens)
  final int burstCapacity;

  const RateLimitMetrics({
    required this.tokensAvailable,
    required this.tokensConsumed,
    required this.messagesBlocked,
    required this.currentRate,
    required this.maxRate,
    required this.burstCapacity,
  });

  /// Calculate utilization as percentage (0.0 - 1.0).
  double get utilization => currentRate / maxRate;

  /// Check if rate limiter is near capacity.
  bool get isNearCapacity => utilization > 0.8;

  @override
  String toString() {
    return '''
RateLimitMetrics:
  Tokens Available: $tokensAvailable / $burstCapacity
  Tokens Consumed: $tokensConsumed
  Messages Blocked: $messagesBlocked
  Current Rate: ${currentRate.toStringAsFixed(1)} / $maxRate msgs/sec
  Utilization: ${(utilization * 100).toStringAsFixed(1)}%
''';
  }
}

/// Internal class to track token consumption events for rate calculation.
class _TokenEvent {
  final DateTime timestamp;

  _TokenEvent({required this.timestamp});
}
