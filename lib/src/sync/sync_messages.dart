import '../core/op_log.dart';

/// Request for synchronization data from a peer.
///
/// Sent when a device wants to sync with another device.
/// The sinceCursor indicates which operations have already been received.
///
/// Example payload:
/// ```json
/// {
///   "sinceCursor": 42,
///   "entity": "task"
/// }
/// ```
class SyncRequest {
  /// Cursor indicating last received operation
  /// (0 means full sync, >0 means incremental)
  final int sinceCursor;

  /// Entity type to sync (e.g., "task", "user")
  /// Null means sync all entities
  final String? entity;

  const SyncRequest({required this.sinceCursor, this.entity});

  Map<String, dynamic> toJson() {
    return {'sinceCursor': sinceCursor, if (entity != null) 'entity': entity};
  }

  factory SyncRequest.fromJson(Map<String, dynamic> json) {
    return SyncRequest(
      sinceCursor: json['sinceCursor'] as int,
      entity: json['entity'] as String?,
    );
  }

  @override
  String toString() {
    final cursor = sinceCursor == 0 ? 'FULL' : 'since $sinceCursor';
    final entityStr = entity ?? 'ALL';
    return 'SyncRequest($cursor, entity: $entityStr)';
  }
}

/// Response containing synchronization data.
///
/// Sent in response to a SyncRequest, contains operations since the
/// requested cursor.
///
/// Example payload:
/// ```json
/// {
///   "operations": [
///     {"opId": "1", "entity": "task", "opType": "create", ...},
///     {"opId": "2", "entity": "task", "opType": "update", ...}
///   ],
///   "cursor": 45,
///   "totalOperations": 2,
///   "isComplete": true
/// }
/// ```
class SyncResponse {
  /// List of operations to apply
  final List<OpLogEntry> operations;

  /// New cursor position after these operations
  final int cursor;

  /// Total number of operations in this response
  final int totalOperations;

  /// Whether this completes the sync (true) or more chunks coming (false)
  final bool isComplete;

  const SyncResponse({
    required this.operations,
    required this.cursor,
    required this.totalOperations,
    this.isComplete = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'operations': operations.map((op) => op.toJson()).toList(),
      'cursor': cursor,
      'totalOperations': totalOperations,
      'isComplete': isComplete,
    };
  }

  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    final opsJson = json['operations'] as List;

    return SyncResponse(
      operations: opsJson
          .map((opJson) => OpLogEntry.fromJson(opJson as Map<String, dynamic>))
          .toList(),
      cursor: json['cursor'] as int,
      totalOperations: json['totalOperations'] as int,
      isComplete: json['isComplete'] as bool? ?? true,
    );
  }

  @override
  String toString() {
    return 'SyncResponse($totalOperations ops, cursor: $cursor, complete: $isComplete)';
  }
}

/// Notification that an item was created or updated.
///
/// Broadcast to all peers when a local item changes.
/// Peers receive this and update their local storage.
///
/// Example payload:
/// ```json
/// {
///   "item": {"id": "1", "title": "Task 1", ...},
///   "opLogEntry": {"opId": "1", "opType": "create", ...}
/// }
/// ```
class ItemUpsertedMessage {
  /// The item that was created/updated (as JSON)
  final Map<String, dynamic> item;

  /// The operation log entry for this change
  final OpLogEntry opLogEntry;

  const ItemUpsertedMessage({required this.item, required this.opLogEntry});

  Map<String, dynamic> toJson() {
    return {'item': item, 'opLogEntry': opLogEntry.toJson()};
  }

  factory ItemUpsertedMessage.fromJson(Map<String, dynamic> json) {
    return ItemUpsertedMessage(
      item: Map<String, dynamic>.from(json['item'] as Map),
      opLogEntry: OpLogEntry.fromJson(
        json['opLogEntry'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  String toString() {
    return 'ItemUpsertedMessage(item: ${item['id']}, op: ${opLogEntry.opType})';
  }
}

/// Notification that sync is complete.
///
/// Sent after successfully applying all operations from a sync response.
///
/// Example payload:
/// ```json
/// {
///   "cursor": 45,
///   "appliedOperations": 3
/// }
/// ```
class SyncCompleteMessage {
  /// Final cursor position after sync
  final int cursor;

  /// Number of operations that were applied
  final int appliedOperations;

  const SyncCompleteMessage({
    required this.cursor,
    required this.appliedOperations,
  });

  Map<String, dynamic> toJson() {
    return {'cursor': cursor, 'appliedOperations': appliedOperations};
  }

  factory SyncCompleteMessage.fromJson(Map<String, dynamic> json) {
    return SyncCompleteMessage(
      cursor: json['cursor'] as int,
      appliedOperations: json['appliedOperations'] as int,
    );
  }

  @override
  String toString() {
    return 'SyncCompleteMessage(cursor: $cursor, applied: $appliedOperations)';
  }
}
