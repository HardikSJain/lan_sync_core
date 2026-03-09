import 'dart:convert';

import 'message_envelope.dart';

/// Encodes and decodes UDP wire messages.
///
/// This is intentionally thin: transport concerns stay out, and higher-level
/// sync orchestration remains separate. The goal is to make the protocol easy
/// to test independently from sockets.
class MessageProtocol {
  const MessageProtocol();

  /// Encodes an envelope into a JSON UTF-8 byte payload.
  List<int> encode(MessageEnvelope envelope) {
    return utf8.encode(jsonEncode(envelope.toJson()));
  }

  /// Decodes a UTF-8 JSON payload into a [MessageEnvelope].
  MessageEnvelope decode(List<int> bytes) {
    final decoded = utf8.decode(bytes);
    final json = jsonDecode(decoded);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Message payload must be a JSON object');
    }
    return MessageEnvelope.fromJson(json);
  }

  /// Estimates encoded payload size in bytes.
  int estimateSizeBytes(MessageEnvelope envelope) {
    return utf8.encode(jsonEncode(envelope.toJson())).length;
  }
}
