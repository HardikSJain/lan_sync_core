import 'dart:async';

import '../core/op_log.dart';
import '../core/sync_event_handler.dart';
import '../core/sync_item.dart';
import '../core/sync_serializer.dart';
import '../core/sync_storage_adapter.dart';
import '../monitoring/peer_tracker.dart';
import '../network/message_envelope.dart';
import '../network/message_type.dart';
import '../network/udp_transport.dart';
import 'conflict_resolver.dart';
import 'sync_messages.dart';

/// Coordinates synchronization flows between devices.
///
/// The SyncCoordinator is a state machine that manages:
/// - Full sync requests and responses
/// - Incremental sync with cursor tracking
/// - Concurrent sync sessions with multiple peers
/// - Conflict detection and resolution
/// - Operation log integration
///
/// State flow:
/// ```
/// IDLE → SYNCING → APPLYING → IDLE
///   ↓                             ↑
///   └─────────── ERROR ──────────┘
/// ```
///
/// Example:
/// ```dart
/// final coordinator = SyncCoordinator<Task>(
///   storage: taskStorage,
///   serializer: taskSerializer,
///   transport: udpTransport,
///   opLog: fileOpLog,
///   eventHandler: myEventHandler,
///   conflictResolver: LastWriteWinsResolver(),
/// );
///
/// // Sync with a peer
/// await coordinator.syncWithPeer(peerInfo);
///
/// // Handle incoming sync request
/// await coordinator.handleIncomingSyncRequest(peerId, request);
///
/// // Broadcast item change
/// await coordinator.broadcastItemChange(task);
/// ```
class SyncCoordinator<T extends SyncItem> {
  final SyncStorageAdapter<T> storage;
  final SyncSerializer<T> serializer;
  final UdpTransport transport;
  final OpLogAdapter opLog;
  final SyncEventHandler eventHandler;
  final ConflictResolver<T> conflictResolver;

  /// Active sync sessions (peer device ID → sync state)
  final Map<String, _SyncSession> _activeSessions = {};

  /// Stream controller for sync events
  final _eventController = StreamController<SyncEvent>.broadcast();

  /// Stream of sync events
  Stream<SyncEvent> get events => _eventController.stream;

  /// Current sync status
  SyncStatus _status = SyncStatus.idle;

  SyncCoordinator({
    required this.storage,
    required this.serializer,
    required this.transport,
    required this.opLog,
    required this.eventHandler,
    required this.conflictResolver,
  });

  /// Initiate sync with a peer.
  ///
  /// Sends a SYNC_REQUEST and waits for SYNC_RESPONSE.
  /// Returns the result of the sync operation.
  Future<SyncResult> syncWithPeer(PeerInfo peer) async {
    final peerId = peer.deviceId;

    // Check if already syncing with this peer
    if (_activeSessions.containsKey(peerId)) {
      return SyncResult(
        success: false,
        error: 'Already syncing with peer $peerId',
      );
    }

    try {
      // Create sync session
      final session = _SyncSession(
        peerId: peerId,
        startedAt: DateTime.now(),
        state: SyncSessionState.requesting,
      );
      _activeSessions[peerId] = session;

      // Get cursor (last synced position)
      final cursor = await _getCursorForPeer(peerId);

      // Create sync request
      final request = SyncRequest(sinceCursor: cursor);

      // Send sync request
      final envelope = MessageEnvelope(
        type: MessageType.syncRequest,
        deviceId: await _getOurDeviceId(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: request.toJson(),
      );

      await transport.sendTo(peer.address, envelope);

      // Update session state
      session.state = SyncSessionState.waiting;
      session.requestSentAt = DateTime.now();

      // Emit event
      _emitEvent(SyncEventType.syncStarted, peerId: peerId);

      return SyncResult(success: true, cursor: cursor);
    } catch (e) {
      _activeSessions.remove(peerId);
      _emitEvent(SyncEventType.syncFailed, peerId: peerId, error: e.toString());

      return SyncResult(success: false, error: e.toString());
    }
  }

  /// Handle incoming sync request from a peer.
  ///
  /// Reads operations since the requested cursor and sends a SYNC_RESPONSE.
  Future<void> handleIncomingSyncRequest(
    String peerId,
    SyncRequest request,
  ) async {
    try {
      // Get operations since cursor
      final operations = await opLog.getOpsSince(
        request.sinceCursor,
        limit: 1000, // Batch size
      );

      // Get current cursor
      final currentCursor = opLog.lastOpId;

      // Create sync response
      final response = SyncResponse(
        operations: operations,
        cursor: currentCursor,
        totalOperations: operations.length,
        isComplete: true,
      );

      // Send sync response
      final envelope = MessageEnvelope(
        type: MessageType.syncResponse,
        deviceId: await _getOurDeviceId(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: response.toJson(),
      );

      // Get peer info to send response
      final peer = await _findPeerById(peerId);
      if (peer != null) {
        await transport.sendTo(peer.address, envelope);

        _emitEvent(
          SyncEventType.syncResponseSent,
          peerId: peerId,
          operationCount: operations.length,
        );
      }
    } catch (e) {
      _emitEvent(SyncEventType.syncFailed, peerId: peerId, error: e.toString());
    }
  }

  /// Handle incoming sync response from a peer.
  ///
  /// Applies operations, resolves conflicts, updates storage and cursor.
  Future<void> handleIncomingSyncResponse(
    String peerId,
    SyncResponse response,
  ) async {
    final session = _activeSessions[peerId];
    if (session == null) {
      // No active session - might be unsolicited response
      return;
    }

    try {
      session.state = SyncSessionState.applying;

      var appliedCount = 0;

      // Apply each operation
      for (final opEntry in response.operations) {
        try {
          // Deserialize item from operation payload
          final item = serializer.itemFromJson(opEntry.payload);

          // Check for existing item
          final existing = await storage.getItemBySyncId(item.syncId);

          if (existing != null) {
            // Check for conflict
            if (conflictResolver.hasConflict(existing, item)) {
              // Resolve conflict
              final winner = conflictResolver.resolve(existing, item);

              // Update storage with winner
              await storage.upsertItem(winner);

              _emitEvent(
                SyncEventType.conflictResolved,
                peerId: peerId,
                itemId: item.syncId,
              );
            } else {
              // No conflict - update normally
              await storage.upsertItem(item);
            }
          } else {
            // New item - insert
            await storage.upsertItem(item);
          }

          // Record operation in our log
          await opLog.recordExternalOp(opEntry);

          // Call event handler for each item
          eventHandler.onItemReceived(item);

          appliedCount++;
        } catch (e) {
          // Skip failed operations but continue
          _emitEvent(
            SyncEventType.operationFailed,
            peerId: peerId,
            error: e.toString(),
          );
          continue;
        }
      }

      // Update cursor for this peer
      await _updateCursorForPeer(peerId, response.cursor);

      // Mark session complete
      session.state = SyncSessionState.complete;
      session.completedAt = DateTime.now();

      // Remove session after a delay
      Future.delayed(const Duration(seconds: 30), () {
        _activeSessions.remove(peerId);
      });

      // Emit completion event
      _emitEvent(
        SyncEventType.syncCompleted,
        peerId: peerId,
        operationCount: appliedCount,
      );

      // Call event handler
      eventHandler.onSyncCompleted(appliedCount);
    } catch (e) {
      session.state = SyncSessionState.failed;
      _activeSessions.remove(peerId);

      _emitEvent(SyncEventType.syncFailed, peerId: peerId, error: e.toString());

      eventHandler.onSyncFailed(e.toString());
    }
  }

  /// Broadcast an item change to all peers.
  ///
  /// Used when a local item is created or updated.
  Future<void> broadcastItemChange(T item) async {
    try {
      // Create operation log entry
      final opEntry = await opLog.appendLocalOp(
        entity: _getEntityType(),
        opType: 'upsert',
        payload: item.toJson(),
      );

      // Create item upserted message
      final message = ItemUpsertedMessage(
        item: item.toJson(),
        opLogEntry: opEntry,
      );

      // Broadcast to all peers
      final envelope = MessageEnvelope(
        type: MessageType.itemUpserted,
        deviceId: await _getOurDeviceId(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: message.toJson(),
      );

      await transport.broadcast(envelope);

      _emitEvent(SyncEventType.itemBroadcast, itemId: item.syncId);
    } catch (e) {
      _emitEvent(SyncEventType.operationFailed, error: e.toString());
    }
  }

  /// Handle incoming item upserted message.
  ///
  /// Applies the item change to local storage.
  Future<void> handleItemUpserted(
    String peerId,
    ItemUpsertedMessage message,
  ) async {
    try {
      // Deserialize item
      final item = serializer.itemFromJson(message.item);

      // Check for existing item
      final existing = await storage.getItemBySyncId(item.syncId);

      if (existing != null) {
        // Check for conflict
        if (conflictResolver.hasConflict(existing, item)) {
          // Resolve conflict
          final winner = conflictResolver.resolve(existing, item);
          await storage.upsertItem(winner);

          _emitEvent(
            SyncEventType.conflictResolved,
            peerId: peerId,
            itemId: item.syncId,
          );
        } else {
          // No conflict - update normally
          await storage.upsertItem(item);
        }
      } else {
        // New item - insert
        await storage.upsertItem(item);
      }

      // Record operation in our log
      await opLog.recordExternalOp(message.opLogEntry);

      // Call event handler
      eventHandler.onItemReceived(item);
    } catch (e) {
      _emitEvent(
        SyncEventType.operationFailed,
        peerId: peerId,
        error: e.toString(),
      );
    }
  }

  /// Get current sync status.
  SyncStatus getStatus() => _status;

  /// Clean up stale sync sessions.
  ///
  /// Removes sessions that have been pending for too long.
  void cleanupStaleSessions({Duration timeout = const Duration(minutes: 5)}) {
    final now = DateTime.now();
    _activeSessions.removeWhere((peerId, session) {
      final age = now.difference(session.startedAt);
      if (age > timeout && session.state != SyncSessionState.complete) {
        _emitEvent(
          SyncEventType.syncFailed,
          peerId: peerId,
          error: 'Session timeout',
        );
        return true;
      }
      return false;
    });
  }

  /// Dispose of resources.
  void dispose() {
    _eventController.close();
    _activeSessions.clear();
  }

  /// Get cursor for a specific peer.
  Future<int> _getCursorForPeer(String peerId) async {
    // In a real implementation, this would be persisted per-peer
    // For now, return 0 for full sync
    return 0;
  }

  /// Update cursor for a specific peer.
  Future<void> _updateCursorForPeer(String peerId, int cursor) async {
    // In a real implementation, persist the cursor per-peer
    // For now, just track in memory
  }

  /// Get our device ID.
  Future<String> _getOurDeviceId() async {
    // This should come from device identity provider
    // For now, use a placeholder
    return 'our-device-id';
  }

  /// Find a peer by device ID.
  Future<PeerInfo?> _findPeerById(String peerId) async {
    // This should query the peer tracker
    // For now, return null (will be wired up in SyncEngine)
    return null;
  }

  /// Get entity type from generic type.
  String _getEntityType() {
    return T.toString().toLowerCase();
  }

  /// Emit a sync event.
  void _emitEvent(
    SyncEventType type, {
    String? peerId,
    String? itemId,
    int? operationCount,
    String? error,
  }) {
    _eventController.add(
      SyncEvent(
        type: type,
        timestamp: DateTime.now(),
        peerId: peerId,
        itemId: itemId,
        operationCount: operationCount,
        error: error,
      ),
    );
  }
}

/// Internal sync session state tracker.
class _SyncSession {
  final String peerId;
  final DateTime startedAt;
  SyncSessionState state;
  DateTime? requestSentAt;
  DateTime? completedAt;

  _SyncSession({
    required this.peerId,
    required this.startedAt,
    required this.state,
  });
}

/// Sync session state.
enum SyncSessionState { requesting, waiting, applying, complete, failed }

/// Result of a sync operation.
class SyncResult {
  final bool success;
  final int? cursor;
  final String? error;

  const SyncResult({required this.success, this.cursor, this.error});

  @override
  String toString() {
    return 'SyncResult(success: $success, cursor: $cursor, error: $error)';
  }
}

/// Overall sync engine status.
enum SyncStatus { idle, syncing, error }

/// Sync event for monitoring.
class SyncEvent {
  final SyncEventType type;
  final DateTime timestamp;
  final String? peerId;
  final String? itemId;
  final int? operationCount;
  final String? error;

  const SyncEvent({
    required this.type,
    required this.timestamp,
    this.peerId,
    this.itemId,
    this.operationCount,
    this.error,
  });

  @override
  String toString() {
    return 'SyncEvent($type, peer: $peerId, item: $itemId, ops: $operationCount, error: $error)';
  }
}

/// Types of sync events.
enum SyncEventType {
  syncStarted,
  syncResponseSent,
  syncCompleted,
  syncFailed,
  conflictResolved,
  operationFailed,
  itemBroadcast,
}
