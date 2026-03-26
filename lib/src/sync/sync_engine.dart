import 'dart:async';

import '../core/device_identity_provider.dart';
import '../core/op_log.dart';
import '../core/sync_config.dart';
import '../core/sync_event_handler.dart';
import '../core/sync_item.dart';
import '../core/sync_serializer.dart';
import '../core/sync_storage_adapter.dart';
import '../defaults/file_device_identity.dart';
import '../defaults/file_op_log.dart';
import '../monitoring/peer_tracker.dart';
import '../network/message_envelope.dart';
import '../network/message_type.dart';
import '../network/udp_transport.dart';
import 'conflict_resolver.dart';
import 'cursor_storage.dart';
import 'message_router.dart';
import 'sync_coordinator.dart';

/// High-level synchronization engine for LAN-based data sync.
///
/// SyncEngine is the main entry point for `lan_sync_core`. It:
/// - Initializes and wires all components
/// - Manages lifecycle (start/stop/dispose)
/// - Provides simple sync operations
/// - Handles automatic reconnection
/// - Streams unified events for UI reactivity
///
/// ## Usage
///
/// ```dart
/// // Create engine
/// final engine = await SyncEngine.create<Task>(
///   storage: taskStorage,
///   serializer: taskSerializer,
///   eventHandler: myEventHandler,
///   config: SyncConfig(),
/// );
///
/// // Start sync
/// await engine.start();
///
/// // Sync with all peers
/// await engine.syncWithAll();
///
/// // Broadcast change
/// await engine.broadcastChange(task);
///
/// // Listen to events
/// engine.events.listen((event) {
///   print('Sync event: $event');
/// });
///
/// // Stop
/// await engine.stop();
///
/// // Cleanup
/// await engine.dispose();
/// ```
///
/// ## Architecture
///
/// ```
/// SyncEngine (you are here)
///       ↓
/// SyncCoordinator (state machine)
///       ↓
/// UdpTransport + PeerTracker + Monitoring
/// ```
class SyncEngine<T extends SyncItem> {
  // User-provided components
  final SyncStorageAdapter<T> storage;
  final SyncSerializer<T> serializer;
  final SyncEventHandler eventHandler;
  final SyncConfig config;

  // Optional user-provided components
  final ConflictResolver<T>? conflictResolver;
  final DeviceIdentityProvider? deviceIdentity;
  final OpLogAdapter? opLog;
  final CursorStorageAdapter? cursorStorage;

  // Internal components (initialized in create())
  late final DeviceIdentityProvider _deviceIdentity;
  late final OpLogAdapter _opLog;
  late final CursorStorageAdapter _cursorStorage;
  late final ConflictResolver<T> _conflictResolver;
  late final UdpTransport _transport;
  late final PeerTracker _peerTracker;
  late final SyncCoordinator<T> _coordinator;
  late final MessageRouter<T> _router;

  // Lifecycle state
  bool _isStarted = false;
  bool _isDisposed = false;

  // Timers for periodic tasks
  Timer? _heartbeatTimer;
  Timer? _syncTimer;
  Timer? _cleanupTimer;

  // Event stream
  final _eventController = StreamController<SyncEngineEvent>.broadcast();

  /// Stream of sync engine events.
  Stream<SyncEngineEvent> get events => _eventController.stream;

  /// Private constructor - use [create] factory.
  SyncEngine._({
    required this.storage,
    required this.serializer,
    required this.eventHandler,
    required this.config,
    this.conflictResolver,
    this.deviceIdentity,
    this.opLog,
    this.cursorStorage,
  });

  /// Create and initialize a SyncEngine.
  ///
  /// This factory method:
  /// 1. Initializes all internal components
  /// 2. Wires them together
  /// 3. Sets up message routing
  /// 4. Returns ready-to-use engine
  ///
  /// Optional components default to file-based implementations:
  /// - [conflictResolver]: Defaults to LastWriteWinsResolver
  /// - [deviceIdentity]: Defaults to FileDeviceIdentity
  /// - [opLog]: Defaults to FileOpLog
  /// - [cursorStorage]: Defaults to FileCursorStorage
  ///
  /// Example:
  /// ```dart
  /// final engine = await SyncEngine.create<Task>(
  ///   storage: taskStorage,
  ///   serializer: taskSerializer,
  ///   eventHandler: myEventHandler,
  ///   config: SyncConfig.minimal(),
  /// );
  /// ```
  static Future<SyncEngine<T>> create<T extends SyncItem>({
    required SyncStorageAdapter<T> storage,
    required SyncSerializer<T> serializer,
    required SyncEventHandler eventHandler,
    SyncConfig config = const SyncConfig(),
    ConflictResolver<T>? conflictResolver,
    DeviceIdentityProvider? deviceIdentity,
    OpLogAdapter? opLog,
    CursorStorageAdapter? cursorStorage,
  }) async {
    final engine = SyncEngine<T>._(
      storage: storage,
      serializer: serializer,
      eventHandler: eventHandler,
      config: config,
      conflictResolver: conflictResolver,
      deviceIdentity: deviceIdentity,
      opLog: opLog,
      cursorStorage: cursorStorage,
    );

    await engine._initialize();
    return engine;
  }

  /// Initialize all internal components.
  Future<void> _initialize() async {
    // 1. Device identity
    _deviceIdentity =
        deviceIdentity ??
        FileDeviceIdentity(filePath: '.lan_sync/device_id.txt');

    // 2. Operation log
    final providedOpLog = opLog;
    if (providedOpLog != null) {
      _opLog = providedOpLog;
    } else {
      final fileOpLog = FileOpLog(
        filePath: '.lan_sync/oplog.ndjson',
        deviceIdentity: _deviceIdentity,
      );
      await fileOpLog.initialize();
      _opLog = fileOpLog;
    }

    // 3. Cursor storage
    _cursorStorage =
        cursorStorage ?? FileCursorStorage('.lan_sync/cursors.json');
    if (_cursorStorage is FileCursorStorage) {
      await _cursorStorage.load();
    }

    // 4. Conflict resolver
    _conflictResolver = conflictResolver ?? LastWriteWinsResolver<T>();

    // 5. Network components
    _transport = UdpTransport(
      config: UdpTransportConfig(
        port: config.broadcastPort,
        broadcastPort: config.broadcastPort,
      ),
    );

    _peerTracker = PeerTracker();

    // 6. Sync coordinator
    _coordinator = SyncCoordinator<T>(
      storage: storage,
      serializer: serializer,
      transport: _transport,
      opLog: _opLog,
      eventHandler: eventHandler,
      conflictResolver: _conflictResolver,
      deviceIdentity: _deviceIdentity,
      peerTracker: _peerTracker,
      cursorStorage: _cursorStorage,
    );

    // 7. Message router
    _router = MessageRouter<T>(
      coordinator: _coordinator,
      peerTracker: _peerTracker,
      onRoutingError: (error, envelope) {
        _emitEvent(SyncEngineEventType.error, error: error);
      },
    );

    // 8. Wire coordinator events to engine events
    _coordinator.events.listen((event) {
      _emitEvent(
        _mapCoordinatorEventType(event.type),
        peerId: event.peerId,
        itemId: event.itemId,
        count: event.operationCount,
        error: event.error,
      );
    });
  }

  /// Start the sync engine.
  ///
  /// This:
  /// - Starts UDP transport
  /// - Begins heartbeat broadcasting
  /// - Enables automatic sync
  /// - Starts peer cleanup
  ///
  /// Safe to call multiple times (idempotent).
  Future<void> start() async {
    if (_isStarted || _isDisposed) return;

    // Start UDP transport
    await _transport.start();

    // Wire message routing
    _transport.messages.listen((udpMessage) {
      _router.route(udpMessage.envelope, udpMessage.sourceAddress);
    });

    // Start heartbeat timer
    _heartbeatTimer = Timer.periodic(
      config.heartbeatInterval,
      (_) => _sendHeartbeat(),
    );

    // Start auto-sync timer
    if (config.enableAutoFullSync) {
      _syncTimer = Timer.periodic(
        config.periodicVerificationInterval,
        (_) => syncWithAll(),
      );
    }

    // Start cleanup timer
    _cleanupTimer = Timer.periodic(
      config.cleanupInterval,
      (_) => _cleanupStaleSessions(),
    );

    _isStarted = true;
    _emitEvent(SyncEngineEventType.started);
  }

  /// Stop the sync engine.
  ///
  /// Stops all timers and UDP transport, but keeps state.
  /// Can be restarted with [start].
  Future<void> stop() async {
    if (!_isStarted) return;

    // Stop timers
    _heartbeatTimer?.cancel();
    _syncTimer?.cancel();
    _cleanupTimer?.cancel();

    // Stop UDP transport
    await _transport.stop();

    _isStarted = false;
    _emitEvent(SyncEngineEventType.stopped);
  }

  /// Sync with all active peers.
  ///
  /// Initiates sync with every peer currently known to PeerTracker.
  /// Returns number of sync operations initiated.
  Future<int> syncWithAll() async {
    if (!_isStarted) {
      throw StateError('SyncEngine not started');
    }

    final peers = _coordinator.getActivePeers();
    var count = 0;

    for (final peer in peers) {
      try {
        final result = await _coordinator.syncWithPeer(peer);
        if (result.success) {
          count++;
        }
      } catch (e) {
        _emitEvent(
          SyncEngineEventType.syncFailed,
          peerId: peer.deviceId,
          error: e.toString(),
        );
      }
    }

    return count;
  }

  /// Sync with a specific peer.
  ///
  /// Returns true if sync was initiated successfully.
  Future<bool> syncWithPeer(String peerId) async {
    if (!_isStarted) {
      throw StateError('SyncEngine not started');
    }

    final peer = _peerTracker.getPeer(peerId);
    if (peer == null) {
      _emitEvent(
        SyncEngineEventType.syncFailed,
        peerId: peerId,
        error: 'Peer not found',
      );
      return false;
    }

    try {
      final result = await _coordinator.syncWithPeer(peer);
      return result.success;
    } catch (e) {
      _emitEvent(
        SyncEngineEventType.syncFailed,
        peerId: peerId,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Broadcast an item change to all peers.
  ///
  /// Use this when an item is created or updated locally.
  Future<void> broadcastChange(T item) async {
    if (!_isStarted) {
      throw StateError('SyncEngine not started');
    }

    await _coordinator.broadcastItemChange(item);
  }

  /// Get list of active peers.
  List<String> getActivePeerIds() {
    return _coordinator.getActivePeers().map((peer) => peer.deviceId).toList();
  }

  /// Get number of active peers.
  int get activePeerCount => _peerTracker.activePeerCount;

  /// Dispose of all resources.
  ///
  /// Stops the engine and cleans up all components.
  /// Engine cannot be reused after disposal.
  Future<void> dispose() async {
    if (_isDisposed) return;

    await stop();

    _coordinator.dispose();
    _peerTracker.dispose();
    _eventController.close();
    await _cursorStorage.dispose();

    _isDisposed = true;
  }

  /// Send heartbeat to all peers.
  Future<void> _sendHeartbeat() async {
    try {
      final envelope = MessageEnvelope(
        type: MessageType.heartbeat,
        deviceId: await _deviceIdentity.getDeviceId(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: {},
      );

      await _transport.broadcast(envelope);
      _emitEvent(SyncEngineEventType.heartbeatSent);
    } catch (e) {
      _emitEvent(SyncEngineEventType.error, error: 'Heartbeat failed: $e');
    }
  }

  /// Clean up stale sync sessions.
  void _cleanupStaleSessions() {
    _coordinator.cleanupStaleSessions();
  }

  /// Emit a sync engine event.
  void _emitEvent(
    SyncEngineEventType type, {
    String? peerId,
    String? itemId,
    int? count,
    String? error,
  }) {
    _eventController.add(
      SyncEngineEvent(
        type: type,
        timestamp: DateTime.now(),
        peerId: peerId,
        itemId: itemId,
        count: count,
        error: error,
      ),
    );
  }

  /// Map coordinator event types to engine event types.
  SyncEngineEventType _mapCoordinatorEventType(SyncEventType type) {
    switch (type) {
      case SyncEventType.syncStarted:
        return SyncEngineEventType.syncStarted;
      case SyncEventType.syncResponseSent:
        return SyncEngineEventType.syncResponseSent;
      case SyncEventType.syncCompleted:
        return SyncEngineEventType.syncCompleted;
      case SyncEventType.syncFailed:
        return SyncEngineEventType.syncFailed;
      case SyncEventType.conflictResolved:
        return SyncEngineEventType.conflictResolved;
      case SyncEventType.operationFailed:
        return SyncEngineEventType.operationFailed;
      case SyncEventType.itemBroadcast:
        return SyncEngineEventType.itemBroadcast;
    }
  }
}

/// Sync engine event.
class SyncEngineEvent {
  final SyncEngineEventType type;
  final DateTime timestamp;
  final String? peerId;
  final String? itemId;
  final int? count;
  final String? error;

  const SyncEngineEvent({
    required this.type,
    required this.timestamp,
    this.peerId,
    this.itemId,
    this.count,
    this.error,
  });

  @override
  String toString() {
    return 'SyncEngineEvent($type, peer: $peerId, item: $itemId, count: $count, error: $error)';
  }
}

/// Sync engine event types.
enum SyncEngineEventType {
  started,
  stopped,
  heartbeatSent,
  syncStarted,
  syncResponseSent,
  syncCompleted,
  syncFailed,
  conflictResolved,
  operationFailed,
  itemBroadcast,
  ackTimeout,
  error,
}
