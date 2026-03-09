/// Configuration for LAN synchronization.
///
/// These defaults are tuned for small-to-medium local networks (5–30 devices)
/// on the same Wi‑Fi / LAN.
class SyncConfig {
  const SyncConfig({
    this.broadcastPort = 8888,
    this.broadcastAddress = '255.255.255.255',
    this.protocolVersion = 1,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.peerStaleAfter = const Duration(seconds: 12),
    this.cleanupInterval = const Duration(seconds: 2),
    this.periodicVerificationInterval = const Duration(seconds: 30),
    this.maxChunkBytes = 40000,
    this.maxUdpPayloadSize = 60000,
    this.ackTimeout = const Duration(milliseconds: 220),
    this.maxAckRetries = 3,
    this.enableChecksums = true,
    this.enableAutoFullSync = false,
  });

  /// UDP port used for peer discovery and sync traffic.
  final int broadcastPort;

  /// Broadcast address used for LAN discovery.
  final String broadcastAddress;

  /// Wire protocol version. Increment on breaking protocol changes.
  final int protocolVersion;

  /// Interval between heartbeat broadcasts.
  final Duration heartbeatInterval;

  /// When a peer is considered stale and evicted.
  final Duration peerStaleAfter;

  /// Interval for stale-peer cleanup.
  final Duration cleanupInterval;

  /// Interval for checksum / consistency verification.
  final Duration periodicVerificationInterval;

  /// Soft cap for chunk payload size.
  final int maxChunkBytes;

  /// Hard cap for UDP payload size.
  final int maxUdpPayloadSize;

  /// How long to wait for ACK before retry.
  final Duration ackTimeout;

  /// Maximum ACK retries for critical messages.
  final int maxAckRetries;

  /// Whether checksum-based integrity verification is enabled.
  final bool enableChecksums;

  /// Whether the engine should automatically trigger full syncs.
  final bool enableAutoFullSync;

  SyncConfig copyWith({
    int? broadcastPort,
    String? broadcastAddress,
    int? protocolVersion,
    Duration? heartbeatInterval,
    Duration? peerStaleAfter,
    Duration? cleanupInterval,
    Duration? periodicVerificationInterval,
    int? maxChunkBytes,
    int? maxUdpPayloadSize,
    Duration? ackTimeout,
    int? maxAckRetries,
    bool? enableChecksums,
    bool? enableAutoFullSync,
  }) {
    return SyncConfig(
      broadcastPort: broadcastPort ?? this.broadcastPort,
      broadcastAddress: broadcastAddress ?? this.broadcastAddress,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      peerStaleAfter: peerStaleAfter ?? this.peerStaleAfter,
      cleanupInterval: cleanupInterval ?? this.cleanupInterval,
      periodicVerificationInterval:
          periodicVerificationInterval ?? this.periodicVerificationInterval,
      maxChunkBytes: maxChunkBytes ?? this.maxChunkBytes,
      maxUdpPayloadSize: maxUdpPayloadSize ?? this.maxUdpPayloadSize,
      ackTimeout: ackTimeout ?? this.ackTimeout,
      maxAckRetries: maxAckRetries ?? this.maxAckRetries,
      enableChecksums: enableChecksums ?? this.enableChecksums,
      enableAutoFullSync: enableAutoFullSync ?? this.enableAutoFullSync,
    );
  }
}
