import 'package:lan_sync_core/lan_sync_core.dart';
import 'package:test/test.dart';

void main() {
  group('SyncConfig', () {
    test('has sensible defaults', () {
      const config = SyncConfig();

      expect(config.broadcastPort, 8888);
      expect(config.broadcastAddress, '255.255.255.255');
      expect(config.protocolVersion, 1);
      expect(config.maxChunkBytes, 40000);
      expect(config.enableChecksums, isTrue);
      expect(config.enableAutoFullSync, isFalse);
    });

    test('copyWith overrides selected values', () {
      const config = SyncConfig();
      final updated = config.copyWith(
        broadcastPort: 9999,
        enableAutoFullSync: true,
      );

      expect(updated.broadcastPort, 9999);
      expect(updated.enableAutoFullSync, isTrue);
      expect(updated.broadcastAddress, config.broadcastAddress);
    });
  });

  group('OpLogEntry', () {
    test('serializes and deserializes correctly', () {
      final entry = OpLogEntry(
        opId: 'device-1:1',
        timestamp: 123456789,
        entity: 'task',
        opType: 'create',
        payload: {'title': 'Test'},
        sourceDeviceId: 'device-1',
        logIndex: 1,
      );

      final json = entry.toJson();
      final decoded = OpLogEntry.fromJson(json);

      expect(decoded.opId, entry.opId);
      expect(decoded.timestamp, entry.timestamp);
      expect(decoded.entity, entry.entity);
      expect(decoded.opType, entry.opType);
      expect(decoded.payload, entry.payload);
      expect(decoded.sourceDeviceId, entry.sourceDeviceId);
      expect(decoded.logIndex, entry.logIndex);
    });

    test('copyWith updates only selected fields', () {
      final entry = OpLogEntry(
        opId: 'device-1:1',
        timestamp: 123,
        entity: 'task',
        opType: 'create',
        payload: {'a': 1},
      );

      final updated = entry.copyWith(opType: 'update', logIndex: 2);

      expect(updated.opId, entry.opId);
      expect(updated.opType, 'update');
      expect(updated.logIndex, 2);
      expect(updated.payload, entry.payload);
    });
  });

  group('SyncItem contract example', () {
    test('example item satisfies core expectations', () {
      final item = _TestItem(
        syncId: 'item-1',
        createdAt: DateTime.utc(2026, 3, 9, 10),
        updatedAt: DateTime.utc(2026, 3, 9, 11),
        sourceDeviceId: 'device-a',
        value: 'hello',
      );

      final json = item.toJson();

      expect(item.syncId, 'item-1');
      expect(item.sourceDeviceId, 'device-a');
      expect(json['value'], 'hello');
      expect(json['syncId'], 'item-1');
    });
  });
}

class _TestItem implements SyncItem {
  _TestItem({
    required this.syncId,
    required this.createdAt,
    required this.updatedAt,
    required this.sourceDeviceId,
    required this.value,
  });

  @override
  final String syncId;

  @override
  final DateTime createdAt;

  @override
  final DateTime updatedAt;

  @override
  final String sourceDeviceId;

  final String value;

  @override
  Map<String, dynamic> toJson() => {
    'syncId': syncId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'sourceDeviceId': sourceDeviceId,
    'value': value,
  };
}
