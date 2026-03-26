import 'dart:io';

import '../core/sync_item.dart';
import '../monitoring/peer_tracker.dart';
import '../network/message_envelope.dart';
import '../network/message_type.dart';
import 'sync_coordinator.dart';
import 'sync_messages.dart';

/// Routes incoming network messages to appropriate handlers.
///
/// The MessageRouter acts as a central dispatcher that:
/// - Receives messages from UdpTransport
/// - Parses message type
/// - Routes to appropriate handler (SyncCoordinator, PeerTracker, etc.)
/// - Handles errors gracefully
///
/// ## Architecture
///
/// ```
/// UdpTransport.onMessage
///       ↓
///  MessageRouter
///       ↓
///   ┌─────────────────────────┐
///   │ Message Type Routing    │
///   ├─────────────────────────┤
///   │ SYNC_REQUEST           │ → SyncCoordinator.handleIncomingSyncRequest()
///   │ SYNC_RESPONSE          │ → SyncCoordinator.handleIncomingSyncResponse()
///   │ ITEM_UPSERTED          │ → SyncCoordinator.handleItemUpserted()
///   │ SYNC_COMPLETE          │ → Event handler (informational)
///   │ HEARTBEAT              │ → PeerTracker.recordHeartbeat()
///   │ PEER_DISCOVERED        │ → PeerTracker (future)
///   └─────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```dart
/// final router = MessageRouter<Task>(
///   coordinator: syncCoordinator,
///   peerTracker: peerTracker,
/// );
///
/// // Wire to UDP transport
/// transport.onMessage = (envelope, address) {
///   router.route(envelope, address);
/// };
/// ```
///
/// ## Error Handling
///
/// - Malformed messages are logged and dropped
/// - Unknown message types are logged and dropped
/// - Handler exceptions are caught and logged
/// - Does not throw exceptions (defensive)
class MessageRouter<T extends SyncItem> {
  final SyncCoordinator<T> coordinator;
  final PeerTracker peerTracker;

  /// Optional callback for unknown message types
  final void Function(MessageType type, MessageEnvelope envelope)?
  onUnknownMessageType;

  /// Optional callback for routing errors
  final void Function(String error, MessageEnvelope envelope)? onRoutingError;

  MessageRouter({
    required this.coordinator,
    required this.peerTracker,
    this.onUnknownMessageType,
    this.onRoutingError,
  });

  /// Route a message to the appropriate handler.
  ///
  /// This method never throws - all errors are caught and logged.
  Future<void> route(MessageEnvelope envelope, InternetAddress address) async {
    try {
      switch (envelope.type) {
        case MessageType.syncRequest:
          await _handleSyncRequest(envelope);
          break;

        case MessageType.syncResponse:
          await _handleSyncResponse(envelope);
          break;

        case MessageType.itemUpserted:
          await _handleItemUpserted(envelope);
          break;

        case MessageType.heartbeat:
          _handleHeartbeat(envelope, address);
          break;

        case MessageType.announcement:
          // Handle peer announcement (discovery)
          _handleAnnouncement(envelope, address);
          break;

        case MessageType.syncResponseChunk:
        case MessageType.syncResendRequest:
        case MessageType.ack:
        case MessageType.checksumVerify:
          // These are handled by lower layers (ChunkManager, AckTracker)
          // Not routing to SyncCoordinator
          break;
      }
    } catch (e, stackTrace) {
      final error = 'Message routing error: $e\n$stackTrace';
      onRoutingError?.call(error, envelope);
    }
  }

  /// Handle SYNC_REQUEST message.
  Future<void> _handleSyncRequest(MessageEnvelope envelope) async {
    try {
      final payload = envelope.payload;
      if (payload == null) {
        onRoutingError?.call('SyncRequest has null payload', envelope);
        return;
      }

      final request = SyncRequest.fromJson(payload);
      await coordinator.handleIncomingSyncRequest(envelope.deviceId, request);
    } catch (e) {
      onRoutingError?.call('Failed to parse/handle SyncRequest: $e', envelope);
    }
  }

  /// Handle SYNC_RESPONSE message.
  Future<void> _handleSyncResponse(MessageEnvelope envelope) async {
    try {
      final payload = envelope.payload;
      if (payload == null) {
        onRoutingError?.call('SyncResponse has null payload', envelope);
        return;
      }

      final response = SyncResponse.fromJson(payload);
      await coordinator.handleIncomingSyncResponse(envelope.deviceId, response);
    } catch (e) {
      onRoutingError?.call('Failed to parse/handle SyncResponse: $e', envelope);
    }
  }

  /// Handle ITEM_UPSERTED message.
  Future<void> _handleItemUpserted(MessageEnvelope envelope) async {
    try {
      final payload = envelope.payload;
      if (payload == null) {
        onRoutingError?.call('ItemUpserted has null payload', envelope);
        return;
      }

      final message = ItemUpsertedMessage.fromJson(payload);
      await coordinator.handleItemUpserted(envelope.deviceId, message);
    } catch (e) {
      onRoutingError?.call('Failed to parse/handle ItemUpserted: $e', envelope);
    }
  }

  /// Handle HEARTBEAT message.
  void _handleHeartbeat(MessageEnvelope envelope, InternetAddress address) {
    try {
      // Create/update peer info from heartbeat
      final peerInfo = PeerInfo(
        deviceId: envelope.deviceId,
        address: address,
        port: 0, // Port will be set by actual UDP layer
        lastSeen: DateTime.fromMillisecondsSinceEpoch(envelope.timestamp),
      );
      peerTracker.addPeer(peerInfo);
    } catch (e) {
      onRoutingError?.call('Failed to handle Heartbeat: $e', envelope);
    }
  }

  /// Handle ANNOUNCEMENT message (peer discovery).
  void _handleAnnouncement(MessageEnvelope envelope, InternetAddress address) {
    try {
      // Peer announced itself - add/update in tracker
      final peerInfo = PeerInfo(
        deviceId: envelope.deviceId,
        address: address,
        port: 0,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(envelope.timestamp),
      );
      peerTracker.addPeer(peerInfo);
    } catch (e) {
      onRoutingError?.call('Failed to handle Announcement: $e', envelope);
    }
  }
}
