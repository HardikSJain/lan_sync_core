/// Wire-level message types used by `lan_sync_core` over UDP.
///
/// These message types are intentionally aligned with the current p2p_expo
/// implementation so migration can happen incrementally without blindly copying
/// the old service architecture.
enum MessageType {
  /// Announces device presence and sync capability on the LAN.
  announcement('ANNOUNCEMENT'),

  /// Lightweight keep-alive signal.
  heartbeat('HEARTBEAT'),

  /// Requests a full sync from a peer.
  syncRequest('SYNC_REQUEST'),

  /// Responds with a full sync in one payload.
  syncResponse('SYNC_RESPONSE'),

  /// Responds with a chunk of a larger sync payload.
  syncResponseChunk('SYNC_RESPONSE_CHUNK'),

  /// Requests missing sync chunks to be resent.
  syncResendRequest('SYNC_RESEND_REQUEST'),

  /// Announces a newly created/updated item to peers.
  itemUpserted('ITEM_UPSERTED'),

  /// Acknowledges receipt of a critical message.
  ack('ACK'),

  /// Verifies dataset integrity across peers.
  checksumVerify('CHECKSUM_VERIFY');

  const MessageType(this.wireName);

  /// Exact wire-format name used on the network.
  final String wireName;

  static MessageType? fromWireName(String? value) {
    if (value == null) return null;
    for (final type in MessageType.values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}
