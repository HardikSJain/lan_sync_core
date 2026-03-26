import 'dart:async';
import 'dart:io';

/// Tracks discovered peers and their health status on the local network.
///
/// Manages the lifecycle of peer connections:
/// - Discovery and registration of new peers
/// - Heartbeat monitoring to detect stale peers
/// - Automatic cleanup of disconnected peers
/// - Event stream for peer changes
///
/// Example:
/// ```dart
/// final tracker = PeerTracker();
///
/// // Listen for peer events
/// tracker.peerEvents.listen((event) {
///   switch (event.type) {
///     case PeerEventType.discovered:
///       print('New peer: ${event.peer.deviceId}');
///     case PeerEventType.lost:
///       print('Lost peer: ${event.peer.deviceId}');
///     case PeerEventType.updated:
///       print('Peer updated: ${event.peer.deviceId}');
///   }
/// });
///
/// // Add/update peers
/// tracker.addPeer(PeerInfo(...));
///
/// // Mark peer as seen (heartbeat)
/// tracker.markSeen('device-123');
///
/// // Get active peers
/// final activePeers = tracker.getActivePeers();
/// ```
class PeerTracker {
  /// Duration after which a peer is considered stale without heartbeat
  final Duration staleThreshold;

  /// How often to check for stale peers
  final Duration cleanupInterval;

  /// Map of device ID to peer info
  final Map<String, PeerInfo> _peers = {};

  /// Stream controller for peer events
  final _eventController = StreamController<PeerEvent>.broadcast();

  /// Timer for periodic cleanup
  Timer? _cleanupTimer;

  /// Stream of peer lifecycle events (discovered, lost, updated)
  Stream<PeerEvent> get peerEvents => _eventController.stream;

  PeerTracker({
    this.staleThreshold = const Duration(seconds: 30),
    this.cleanupInterval = const Duration(seconds: 10),
  }) {
    // Start periodic cleanup
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) => removeStale());
  }

  /// Add or update a peer.
  ///
  /// If the peer is new, emits a [PeerEventType.discovered] event.
  /// If the peer already exists, emits a [PeerEventType.updated] event.
  void addPeer(PeerInfo peer) {
    final isNew = !_peers.containsKey(peer.deviceId);

    _peers[peer.deviceId] = peer;

    if (isNew) {
      _eventController.add(
        PeerEvent(type: PeerEventType.discovered, peer: peer),
      );
    } else {
      _eventController.add(PeerEvent(type: PeerEventType.updated, peer: peer));
    }
  }

  /// Mark a peer as seen (updates lastSeen timestamp).
  ///
  /// This should be called when receiving any communication from a peer
  /// to keep them active.
  ///
  /// Returns true if peer was found, false if peer doesn't exist.
  bool markSeen(String deviceId) {
    final existing = _peers[deviceId];

    if (existing == null) {
      return false;
    }

    // Update with new lastSeen timestamp
    final updated = PeerInfo(
      deviceId: existing.deviceId,
      address: existing.address,
      port: existing.port,
      lastSeen: DateTime.now(),
      metadata: existing.metadata,
    );

    _peers[deviceId] = updated;

    _eventController.add(PeerEvent(type: PeerEventType.updated, peer: updated));

    return true;
  }

  /// Get a specific peer by device ID.
  ///
  /// Returns null if peer not found.
  PeerInfo? getPeer(String deviceId) {
    return _peers[deviceId];
  }

  /// Get all active peers (not stale).
  ///
  /// A peer is considered active if it has been seen within the
  /// [staleThreshold] duration.
  ///
  /// Optionally override the stale threshold for this call.
  List<PeerInfo> getActivePeers({Duration? staleThreshold}) {
    final threshold = staleThreshold ?? this.staleThreshold;
    final now = DateTime.now();

    return _peers.values.where((peer) {
      final timeSinceLastSeen = now.difference(peer.lastSeen);
      return timeSinceLastSeen <= threshold;
    }).toList();
  }

  /// Get all peers (including stale ones).
  List<PeerInfo> getAllPeers() {
    return _peers.values.toList();
  }

  /// Remove stale peers that haven't been seen within the threshold.
  ///
  /// Returns a list of device IDs that were removed.
  ///
  /// Emits [PeerEventType.lost] events for each removed peer.
  List<String> removeStale({Duration? staleThreshold}) {
    final threshold = staleThreshold ?? this.staleThreshold;
    final now = DateTime.now();
    final removedIds = <String>[];

    _peers.removeWhere((deviceId, peer) {
      final timeSinceLastSeen = now.difference(peer.lastSeen);
      final isStale = timeSinceLastSeen > threshold;

      if (isStale) {
        removedIds.add(deviceId);
        _eventController.add(PeerEvent(type: PeerEventType.lost, peer: peer));
      }

      return isStale;
    });

    return removedIds;
  }

  /// Remove a specific peer by device ID.
  ///
  /// Returns true if peer was removed, false if peer didn't exist.
  ///
  /// Emits a [PeerEventType.lost] event if peer was removed.
  bool removePeer(String deviceId) {
    final peer = _peers.remove(deviceId);

    if (peer != null) {
      _eventController.add(PeerEvent(type: PeerEventType.lost, peer: peer));
      return true;
    }

    return false;
  }

  /// Get the number of active peers.
  int get activePeerCount => getActivePeers().length;

  /// Get the total number of tracked peers (including stale).
  int get totalPeerCount => _peers.length;

  /// Clear all peers.
  ///
  /// Emits [PeerEventType.lost] events for all peers.
  void clear() {
    final allPeers = _peers.values.toList();

    for (final peer in allPeers) {
      _eventController.add(PeerEvent(type: PeerEventType.lost, peer: peer));
    }

    _peers.clear();
  }

  /// Clean up resources.
  ///
  /// Call this when the tracker is no longer needed to stop timers
  /// and close streams.
  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _eventController.close();
    _peers.clear();
  }
}

/// Information about a discovered peer on the network.
class PeerInfo {
  /// Unique device identifier
  final String deviceId;

  /// IP address of the peer
  final InternetAddress address;

  /// Port the peer is listening on
  final int port;

  /// Last time this peer was seen (for staleness detection)
  final DateTime lastSeen;

  /// Optional metadata about peer capabilities or state
  final Map<String, dynamic>? metadata;

  const PeerInfo({
    required this.deviceId,
    required this.address,
    required this.port,
    required this.lastSeen,
    this.metadata,
  });

  /// Create a copy with updated fields.
  PeerInfo copyWith({
    String? deviceId,
    InternetAddress? address,
    int? port,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
  }) {
    return PeerInfo(
      deviceId: deviceId ?? this.deviceId,
      address: address ?? this.address,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PeerInfo &&
        other.deviceId == deviceId &&
        other.address == address &&
        other.port == port;
  }

  @override
  int get hashCode {
    return Object.hash(deviceId, address, port);
  }

  @override
  String toString() {
    final timeSinceLastSeen = DateTime.now().difference(lastSeen);
    return 'PeerInfo(id: $deviceId, addr: $address:$port, lastSeen: ${timeSinceLastSeen.inSeconds}s ago)';
  }
}

/// Type of peer lifecycle event.
enum PeerEventType {
  /// New peer was discovered
  discovered,

  /// Existing peer was updated (heartbeat received)
  updated,

  /// Peer was lost (stale or explicitly removed)
  lost,
}

/// Event emitted when a peer's status changes.
class PeerEvent {
  /// Type of event
  final PeerEventType type;

  /// The peer this event is about
  final PeerInfo peer;

  const PeerEvent({required this.type, required this.peer});

  @override
  String toString() {
    return 'PeerEvent(type: $type, peer: ${peer.deviceId})';
  }
}
