import '../core/op_log.dart';
import 'message_type.dart';

/// Base wire envelope for UDP messages.
///
/// Every UDP payload in `lan_sync_core` is represented as a JSON map that at
/// minimum contains:
/// - `type`
/// - `deviceId`
/// - `timestamp`
///
/// Additional fields depend on the message type.
class MessageEnvelope {
  MessageEnvelope({
    required this.type,
    required this.deviceId,
    required this.timestamp,
    this.msgId,
    this.targetDeviceId,
    this.payload,
  });

  static const Set<String> reservedKeys = {
    'type',
    'deviceId',
    'timestamp',
    'msgId',
    'targetDeviceId',
  };

  final MessageType type;
  final String deviceId;
  final int timestamp;
  final String? msgId;
  final String? targetDeviceId;
  final Map<String, dynamic>? payload;

  Map<String, dynamic> toJson() {
    final payload = this.payload;
    if (payload != null) {
      final collisions = payload.keys
          .where(reservedKeys.contains)
          .toList(growable: false);
      if (collisions.isNotEmpty) {
        throw ArgumentError.value(
          collisions,
          'payload',
          'Payload keys cannot override reserved envelope headers.',
        );
      }
    }

    return {
      'type': type.wireName,
      'deviceId': deviceId,
      'timestamp': timestamp,
      if (msgId != null) 'msgId': msgId,
      if (targetDeviceId != null) 'targetDeviceId': targetDeviceId,
      if (payload != null) ...payload,
    };
  }

  factory MessageEnvelope.fromJson(Map<String, dynamic> json) {
    final type = MessageType.fromWireName(json['type'] as String?);
    if (type == null) {
      throw FormatException('Unknown message type: ${json['type']}');
    }

    final reservedKeys = <String>{
      'type',
      'deviceId',
      'timestamp',
      'msgId',
      'targetDeviceId',
    };

    final payload = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!reservedKeys.contains(entry.key)) {
        payload[entry.key] = entry.value;
      }
    }

    return MessageEnvelope(
      type: type,
      deviceId: json['deviceId'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
      msgId: json['msgId'] as String?,
      targetDeviceId: json['targetDeviceId'] as String?,
      payload: payload.isEmpty ? null : payload,
    );
  }
}

/// Envelope wrapper for sync item payloads.
class ItemEnvelope {
  ItemEnvelope({required this.item, this.opLogEntry});

  /// Serialized sync item.
  final Map<String, dynamic> item;

  /// Optional operation metadata for range sync / diagnostics.
  final OpLogEntry? opLogEntry;

  Map<String, dynamic> toJson() {
    return {
      'item': item,
      if (opLogEntry != null)
        'opMeta': {
          'opId': opLogEntry!.opId,
          'timestamp': opLogEntry!.timestamp,
          if (opLogEntry!.sourceDeviceId != null)
            'sourceDeviceId': opLogEntry!.sourceDeviceId,
          if (opLogEntry!.logIndex != null) 'logIndex': opLogEntry!.logIndex,
        },
    };
  }

  factory ItemEnvelope.fromJson(Map<String, dynamic> json) {
    final rawItem = json['item'];
    if (rawItem is! Map) {
      throw const FormatException('ItemEnvelope.item must be a JSON object');
    }

    final rawMeta = json['opMeta'];
    OpLogEntry? opLogEntry;
    if (rawMeta is Map) {
      final meta = Map<String, dynamic>.from(rawMeta);
      final opId = meta['opId'] as String?;
      if (opId != null) {
        opLogEntry = OpLogEntry(
          opId: opId,
          timestamp: (meta['timestamp'] as num?)?.toInt() ?? 0,
          entity: 'sync_item',
          opType: 'upsert',
          payload: {'item': Map<String, dynamic>.from(rawItem)},
          sourceDeviceId: meta['sourceDeviceId'] as String?,
          logIndex: (meta['logIndex'] as num?)?.toInt(),
        );
      }
    }

    return ItemEnvelope(
      item: Map<String, dynamic>.from(rawItem),
      opLogEntry: opLogEntry,
    );
  }
}
