/// Represents a single operation in the synchronization log.
///
/// This is used to maintain causal order and ensure consistency across
/// multiple devices. Each operation is uniquely identified and timestamped.
class OpLogEntry {
  /// Globally unique identifier for this operation.
  /// Usually formatted as `deviceId:sequenceNumber`.
  final String opId;

  /// Timestamp when the operation was created (milliseconds since epoch).
  final int timestamp;

  /// The type of entity being operated on (e.g., 'task', 'check_in').
  final String entity;

  /// The type of operation performed (e.g., 'create', 'update', 'delete').
  final String opType;

  /// The data payload for this operation.
  final Map<String, dynamic> payload;

  /// The ID of the device that originally created this operation.
  final String? sourceDeviceId;

  /// Local sequence number in the append-only log.
  /// This is device-specific and used for range-based syncing.
  final int? logIndex;

  OpLogEntry({
    required this.opId,
    required this.timestamp,
    required this.entity,
    required this.opType,
    required this.payload,
    this.sourceDeviceId,
    this.logIndex,
  });

  Map<String, dynamic> toJson() => {
    'opId': opId,
    'timestamp': timestamp,
    'entity': entity,
    'opType': opType,
    'payload': payload,
    if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
    if (logIndex != null) 'logIndex': logIndex,
  };

  factory OpLogEntry.fromJson(Map<String, dynamic> json) => OpLogEntry(
    opId: json['opId'] as String,
    timestamp: (json['timestamp'] as num).toInt(),
    entity: json['entity'] as String,
    opType: json['opType'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    sourceDeviceId: json['sourceDeviceId'] as String?,
    logIndex: (json['logIndex'] as num?)?.toInt(),
  );

  OpLogEntry copyWith({
    String? opId,
    int? timestamp,
    String? entity,
    String? opType,
    Map<String, dynamic>? payload,
    String? sourceDeviceId,
    int? logIndex,
  }) {
    return OpLogEntry(
      opId: opId ?? this.opId,
      timestamp: timestamp ?? this.timestamp,
      entity: entity ?? this.entity,
      opType: opType ?? this.opType,
      payload: payload ?? this.payload,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      logIndex: logIndex ?? this.logIndex,
    );
  }
}

/// Interface for operation log persistence.
///
/// Implementations must provide an append-only log of synchronization
/// operations. This is critical for catching up peers that have been offline.
abstract class OpLogAdapter {
  /// Appends a new local operation to the log.
  Future<OpLogEntry> appendLocalOp({
    required String entity,
    required String opType,
    required Map<String, dynamic> payload,
    String? sourceDeviceId,
  });

  /// Records an operation received from a remote peer.
  ///
  /// Should return null if the operation ID is already known (deduplication).
  Future<OpLogEntry?> recordExternalOp(OpLogEntry entry);

  /// Retrieves operations with a [logIndex] greater than [sinceCursor].
  Future<List<OpLogEntry>> getOpsSince(int sinceCursor, {int limit = 1000});

  /// Returns the highest [logIndex] currently in the log.
  int get lastOpId;

  /// Finds operations associated with specific sync IDs.
  Future<Map<String, OpLogEntry>> findOpsForSyncIds(Iterable<String> syncIds);

  /// Initializes the log storage.
  Future<void> init();

  /// Advances the local cursor without adding entries.
  Future<void> advanceTo(int cursor);
}
