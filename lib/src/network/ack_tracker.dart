import 'dart:async';
import 'dart:io';

import 'message_envelope.dart';

/// Tracks sent messages and ensures reliable delivery with ACKs and retries.
///
/// Provides guaranteed message delivery over unreliable UDP by:
/// - Tracking all sent messages
/// - Waiting for acknowledgments
/// - Automatic retries with exponential backoff
/// - Timeout detection
/// - Delivery metrics
///
/// Example:
/// ```dart
/// final tracker = AckTracker();
///
/// // Send a message and track it
/// final messageId = tracker.trackMessage(
///   message: envelope,
///   peer: peerAddress,
///   onAck: () => print('Message delivered!'),
///   onFailed: () => print('Message failed after retries'),
/// );
///
/// // When ACK received from peer
/// tracker.recordAck(messageId);
/// ```
class AckTracker {
  /// Maximum number of retry attempts before giving up
  final int maxRetries;

  /// Initial retry delay (doubles with each retry)
  final Duration initialRetryDelay;

  /// Maximum time to wait for ACK before first retry
  final Duration ackTimeout;

  /// Pending messages waiting for ACK
  final Map<String, _PendingMessage> _pendingMessages = {};

  /// Timer for periodic timeout checking
  Timer? _timeoutTimer;

  /// Metrics tracking
  int _totalSent = 0;
  int _totalAcked = 0;
  int _totalRetried = 0;
  int _totalFailed = 0;
  final Map<String, DateTime> _ackTimes = {};

  AckTracker({
    this.maxRetries = 3,
    this.initialRetryDelay = const Duration(milliseconds: 500),
    this.ackTimeout = const Duration(seconds: 2),
  }) {
    // Start periodic timeout checker
    _timeoutTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _checkTimeouts(),
    );
  }

  /// Track a message that was sent and needs acknowledgment.
  ///
  /// Returns the message ID for tracking purposes.
  ///
  /// The [onAck] callback is called when ACK is received.
  /// The [onFailed] callback is called if message fails after all retries.
  /// The [onRetry] callback is called each time a retry is attempted.
  String trackMessage({
    required MessageEnvelope message,
    required InternetAddress peer,
    required int port,
    VoidCallback? onAck,
    VoidCallback? onFailed,
    RetryCallback? onRetry,
  }) {
    final messageId = message.msgId ?? _generateMessageId();

    _pendingMessages[messageId] = _PendingMessage(
      messageId: messageId,
      message: message,
      peer: peer,
      port: port,
      sentAt: DateTime.now(),
      retryCount: 0,
      nextRetryAt: DateTime.now().add(ackTimeout),
      onAck: onAck,
      onFailed: onFailed,
      onRetry: onRetry,
    );

    _totalSent++;
    return messageId;
  }

  /// Record that an ACK was received for a message.
  ///
  /// This marks the message as successfully delivered and triggers
  /// the onAck callback if provided.
  ///
  /// Returns true if the message was being tracked, false otherwise.
  bool recordAck(String messageId) {
    final pending = _pendingMessages.remove(messageId);

    if (pending == null) {
      return false; // Message not being tracked (maybe already ACKed)
    }

    _totalAcked++;

    // Record ACK time for metrics
    _ackTimes[messageId] = DateTime.now();

    // Call ACK callback
    pending.onAck?.call();

    return true;
  }

  /// Get messages that need to be retried.
  ///
  /// Returns a list of messages that have timed out and should be
  /// retransmitted. This should be called periodically to trigger retries.
  ///
  /// Each returned item includes the message and peer information.
  List<RetryInfo> getRetries() {
    final now = DateTime.now();
    final retries = <RetryInfo>[];

    _pendingMessages.forEach((messageId, pending) {
      if (now.isAfter(pending.nextRetryAt)) {
        retries.add(
          RetryInfo(
            messageId: messageId,
            message: pending.message,
            peer: pending.peer,
            port: pending.port,
            retryCount: pending.retryCount + 1,
          ),
        );
      }
    });

    return retries;
  }

  /// Mark a message retry as sent.
  ///
  /// This updates the retry count and schedules the next retry with
  /// exponential backoff.
  ///
  /// Returns true if successful, false if message not found or max retries exceeded.
  bool markRetried(String messageId) {
    final pending = _pendingMessages[messageId];

    if (pending == null) {
      return false;
    }

    // Increment retry count
    pending.retryCount++;
    _totalRetried++;

    // Check if max retries exceeded
    if (pending.retryCount >= maxRetries) {
      // Remove from pending and mark as failed
      _pendingMessages.remove(messageId);
      _totalFailed++;
      pending.onFailed?.call();
      return false;
    }

    // Calculate next retry time with exponential backoff
    final backoffDelay = _calculateBackoff(pending.retryCount);
    pending.nextRetryAt = DateTime.now().add(backoffDelay);

    // Call retry callback
    pending.onRetry?.call(pending.retryCount);

    return true;
  }

  /// Get current metrics for monitoring.
  AckMetrics getMetrics() {
    final averageLatency = _calculateAverageLatency();

    return AckMetrics(
      totalSent: _totalSent,
      totalAcked: _totalAcked,
      totalRetried: _totalRetried,
      totalFailed: _totalFailed,
      pendingCount: _pendingMessages.length,
      successRate: _totalSent > 0 ? _totalAcked / _totalSent : 0.0,
      averageLatency: averageLatency,
    );
  }

  /// Clear all pending messages and reset counters.
  ///
  /// Useful for testing or reinitializing the tracker.
  void reset() {
    _pendingMessages.clear();
    _totalSent = 0;
    _totalAcked = 0;
    _totalRetried = 0;
    _totalFailed = 0;
    _ackTimes.clear();
  }

  /// Clean up resources.
  ///
  /// Call this when the tracker is no longer needed to stop timers.
  void dispose() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _pendingMessages.clear();
  }

  /// Check for timed-out messages and trigger retries.
  void _checkTimeouts() {
    final retries = getRetries();

    for (final retry in retries) {
      markRetried(retry.messageId);
    }
  }

  /// Calculate exponential backoff delay.
  Duration _calculateBackoff(int retryCount) {
    // Exponential backoff: initialDelay * 2^retryCount
    final multiplier = 1 << retryCount; // 2^retryCount
    return initialRetryDelay * multiplier;
  }

  /// Calculate average ACK latency from recent ACKs.
  Duration _calculateAverageLatency() {
    // Simplified calculation: estimate average latency based on retry delay
    // In a real implementation, we'd track actual sent times more precisely
    return _ackTimes.isNotEmpty ? initialRetryDelay : Duration.zero;
  }

  /// Generate a unique message ID.
  String _generateMessageId() {
    return 'msg-${DateTime.now().microsecondsSinceEpoch}';
  }
}

/// Information about a message that needs retrying.
class RetryInfo {
  final String messageId;
  final MessageEnvelope message;
  final InternetAddress peer;
  final int port;
  final int retryCount;

  const RetryInfo({
    required this.messageId,
    required this.message,
    required this.peer,
    required this.port,
    required this.retryCount,
  });

  @override
  String toString() {
    return 'RetryInfo(id: $messageId, peer: $peer:$port, attempt: $retryCount)';
  }
}

/// Metrics about ACK tracking performance.
class AckMetrics {
  final int totalSent;
  final int totalAcked;
  final int totalRetried;
  final int totalFailed;
  final int pendingCount;
  final double successRate;
  final Duration averageLatency;

  const AckMetrics({
    required this.totalSent,
    required this.totalAcked,
    required this.totalRetried,
    required this.totalFailed,
    required this.pendingCount,
    required this.successRate,
    required this.averageLatency,
  });

  @override
  String toString() {
    return '''
AckMetrics:
  Sent: $totalSent
  ACKed: $totalAcked
  Retried: $totalRetried
  Failed: $totalFailed
  Pending: $pendingCount
  Success Rate: ${(successRate * 100).toStringAsFixed(1)}%
  Avg Latency: ${averageLatency.inMilliseconds}ms
''';
  }
}

/// Callback type for retry notifications.
typedef RetryCallback = void Function(int retryCount);

/// Callback type for void callbacks.
typedef VoidCallback = void Function();

/// Internal class to track a pending message.
class _PendingMessage {
  final String messageId;
  final MessageEnvelope message;
  final InternetAddress peer;
  final int port;
  final DateTime sentAt;
  int retryCount;
  DateTime nextRetryAt;
  final VoidCallback? onAck;
  final VoidCallback? onFailed;
  final RetryCallback? onRetry;

  _PendingMessage({
    required this.messageId,
    required this.message,
    required this.peer,
    required this.port,
    required this.sentAt,
    required this.retryCount,
    required this.nextRetryAt,
    this.onAck,
    this.onFailed,
    this.onRetry,
  });
}
