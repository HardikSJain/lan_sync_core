import 'package:lan_sync_core/lan_sync_core.dart';
import 'package:test/test.dart';

void main() {
  group('MessageType', () {
    test('round-trips from wire name', () {
      expect(
        MessageType.fromWireName('ANNOUNCEMENT'),
        MessageType.announcement,
      );
      expect(MessageType.fromWireName('ACK'), MessageType.ack);
      expect(MessageType.fromWireName('UNKNOWN'), isNull);
    });
  });

  group('MessageEnvelope', () {
    test('serializes base and payload fields', () {
      final envelope = MessageEnvelope(
        type: MessageType.syncRequest,
        deviceId: 'device-a',
        timestamp: 123,
        msgId: 'msg-1',
        targetDeviceId: 'device-b',
        payload: {'requestingFullSync': true},
      );

      final json = envelope.toJson();
      final decoded = MessageEnvelope.fromJson(json);

      expect(decoded.type, MessageType.syncRequest);
      expect(decoded.deviceId, 'device-a');
      expect(decoded.msgId, 'msg-1');
      expect(decoded.targetDeviceId, 'device-b');
      expect(decoded.payload?['requestingFullSync'], isTrue);
    });

    test('rejects payload keys that collide with reserved headers', () {
      final envelope = MessageEnvelope(
        type: MessageType.syncRequest,
        deviceId: 'device-a',
        timestamp: 123,
        payload: {'type': 'ACK'},
      );

      expect(
        () => envelope.toJson(),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('reserved envelope headers'),
          ),
        ),
      );
    });

    test('throws descriptive error for missing or invalid deviceId', () {
      expect(
        () => MessageEnvelope.fromJson({
          'type': 'SYNC_REQUEST',
          'timestamp': 123,
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains("deviceId"),
          ),
        ),
      );

      expect(
        () => MessageEnvelope.fromJson({
          'type': 'SYNC_REQUEST',
          'deviceId': 42,
          'timestamp': 123,
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains("deviceId"),
          ),
        ),
      );
    });

    test('throws descriptive error for missing or invalid timestamp', () {
      expect(
        () => MessageEnvelope.fromJson({
          'type': 'SYNC_REQUEST',
          'deviceId': 'device-a',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains("timestamp"),
          ),
        ),
      );

      expect(
        () => MessageEnvelope.fromJson({
          'type': 'SYNC_REQUEST',
          'deviceId': 'device-a',
          'timestamp': '123',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains("timestamp"),
          ),
        ),
      );
    });
  });

  group('ItemEnvelope', () {
    test('supports optional op metadata', () {
      final itemEnvelope = ItemEnvelope(
        item: {'syncId': 'item-1', 'title': 'Hello'},
        opLogEntry: OpLogEntry(
          opId: 'device-a:1',
          timestamp: 123,
          entity: 'task',
          opType: 'upsert',
          payload: {
            'item': {'syncId': 'item-1'},
          },
          sourceDeviceId: 'device-a',
          logIndex: 1,
        ),
      );

      final json = itemEnvelope.toJson();
      final decoded = ItemEnvelope.fromJson(json);

      expect(decoded.item['syncId'], 'item-1');
      expect(decoded.opLogEntry?.opId, 'device-a:1');
      expect(decoded.opLogEntry?.logIndex, 1);
    });
  });

  group('MessageProtocol', () {
    test('encodes and decodes payloads', () {
      const protocol = MessageProtocol();
      final envelope = MessageEnvelope(
        type: MessageType.checksumVerify,
        deviceId: 'device-a',
        timestamp: 999,
        payload: {'count': 12, 'checksum': 'abc'},
      );

      final bytes = protocol.encode(envelope);
      final decoded = protocol.decode(bytes);

      expect(decoded.type, MessageType.checksumVerify);
      expect(decoded.payload?['count'], 12);
      expect(decoded.payload?['checksum'], 'abc');
      expect(protocol.estimateSizeBytes(envelope), greaterThan(0));
    });
  });
}
