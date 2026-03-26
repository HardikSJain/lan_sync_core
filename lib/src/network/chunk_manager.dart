import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Manages splitting and reassembly of large messages into UDP-sized chunks.
///
/// UDP packets have a practical size limit of ~60KB. Messages larger than this
/// must be split into chunks, transmitted separately, and reassembled on the
/// receiving end.
///
/// Features:
/// - Automatic chunking of large payloads
/// - Chunk reassembly with missing piece detection
/// - Checksum verification for data integrity
/// - Stale session cleanup
/// - Duplicate chunk handling
class ChunkManager {
  /// Default maximum chunk size (60KB - leaves room for UDP headers)
  static const int defaultMaxChunkSize = 60000;

  /// Maximum time to wait for all chunks before giving up (60 seconds)
  final Duration reassemblyTimeout;

  /// Map of incomplete reassembly sessions
  final Map<String, _ReassemblySession> _activeSessions = {};

  ChunkManager({this.reassemblyTimeout = const Duration(seconds: 60)});

  /// Split a large message into chunks.
  ///
  /// Returns a list of chunks that can be sent individually over UDP.
  /// Each chunk includes metadata for reassembly.
  ///
  /// Example:
  /// ```dart
  /// final data = Uint8List(100000); // 100KB message
  /// final chunks = chunkManager.createChunks(data, messageId: 'msg-123');
  /// for (final chunk in chunks) {
  ///   // Send chunk via UDP...
  /// }
  /// ```
  List<MessageChunk> createChunks(
    Uint8List data, {
    required String messageId,
    int maxChunkSize = defaultMaxChunkSize,
  }) {
    if (data.isEmpty) {
      throw ArgumentError('Cannot chunk empty data');
    }

    // If message fits in one chunk, create single chunk
    if (data.length <= maxChunkSize) {
      return [
        MessageChunk(
          messageId: messageId,
          sequenceNumber: 0,
          totalChunks: 1,
          data: data,
          checksum: _calculateChecksum(data),
        ),
      ];
    }

    // Calculate total number of chunks needed
    final totalChunks = (data.length / maxChunkSize).ceil();
    final chunks = <MessageChunk>[];

    for (var i = 0; i < totalChunks; i++) {
      final start = i * maxChunkSize;
      final end = (start + maxChunkSize < data.length)
          ? start + maxChunkSize
          : data.length;

      final chunkData = data.sublist(start, end);

      chunks.add(
        MessageChunk(
          messageId: messageId,
          sequenceNumber: i,
          totalChunks: totalChunks,
          data: chunkData,
          checksum: _calculateChecksum(chunkData),
        ),
      );
    }

    return chunks;
  }

  /// Add a received chunk to the reassembly buffer.
  ///
  /// Returns a [ReassemblyResult] indicating:
  /// - Whether the message is complete
  /// - The reassembled data (if complete)
  /// - Which chunks are still missing (if incomplete)
  ///
  /// Example:
  /// ```dart
  /// final result = chunkManager.addChunk(chunk);
  /// if (result.isComplete) {
  ///   final completeMessage = result.data!;
  ///   // Process complete message...
  /// } else {
  ///   print('Still waiting for chunks: ${result.missingChunks}');
  /// }
  /// ```
  ReassemblyResult addChunk(MessageChunk chunk) {
    // Verify chunk checksum
    final calculatedChecksum = _calculateChecksum(chunk.data);
    if (calculatedChecksum != chunk.checksum) {
      throw ChunkIntegrityException(
        'Checksum mismatch for chunk ${chunk.sequenceNumber} of ${chunk.messageId}',
      );
    }

    // Get or create reassembly session
    final session = _activeSessions.putIfAbsent(
      chunk.messageId,
      () => _ReassemblySession(
        messageId: chunk.messageId,
        totalChunks: chunk.totalChunks,
        startedAt: DateTime.now(),
      ),
    );

    // Validate chunk belongs to this session
    if (session.totalChunks != chunk.totalChunks) {
      throw ChunkValidationException(
        'Chunk total mismatch: expected ${session.totalChunks}, got ${chunk.totalChunks}',
      );
    }

    // Add chunk to session (handles duplicates automatically)
    session.addChunk(chunk);

    // Check if complete
    if (session.isComplete) {
      final data = session.reassemble();
      _activeSessions.remove(chunk.messageId);

      return ReassemblyResult(isComplete: true, data: data, missingChunks: {});
    }

    // Return incomplete status with missing chunks
    return ReassemblyResult(
      isComplete: false,
      data: null,
      missingChunks: session.getMissingChunks(),
    );
  }

  /// Remove stale reassembly sessions that have timed out.
  ///
  /// Returns the list of message IDs that were cleaned up.
  ///
  /// Should be called periodically (e.g., every 10 seconds) to free memory.
  ///
  /// Example:
  /// ```dart
  /// Timer.periodic(Duration(seconds: 10), (_) {
  ///   final cleaned = chunkManager.cleanupStale();
  ///   if (cleaned.isNotEmpty) {
  ///     print('Cleaned up ${cleaned.length} stale sessions');
  ///   }
  /// });
  /// ```
  List<String> cleanupStale() {
    final now = DateTime.now();
    final staleIds = <String>[];

    _activeSessions.removeWhere((messageId, session) {
      final isStale = now.difference(session.startedAt) > reassemblyTimeout;
      if (isStale) {
        staleIds.add(messageId);
      }
      return isStale;
    });

    return staleIds;
  }

  /// Get the number of active reassembly sessions.
  int get activeSessionCount => _activeSessions.length;

  /// Calculate MD5 checksum for data integrity verification.
  String _calculateChecksum(Uint8List data) {
    return md5.convert(data).toString();
  }
}

/// Represents a single chunk of a larger message.
class MessageChunk {
  /// Unique identifier for the complete message (all chunks share this)
  final String messageId;

  /// Position of this chunk in the sequence (0-indexed)
  final int sequenceNumber;

  /// Total number of chunks in the complete message
  final int totalChunks;

  /// The actual chunk data
  final Uint8List data;

  /// MD5 checksum for integrity verification
  final String checksum;

  const MessageChunk({
    required this.messageId,
    required this.sequenceNumber,
    required this.totalChunks,
    required this.data,
    required this.checksum,
  });

  /// Create chunk from JSON (for wire protocol)
  factory MessageChunk.fromJson(Map<String, dynamic> json) {
    return MessageChunk(
      messageId: json['messageId'] as String,
      sequenceNumber: json['sequenceNumber'] as int,
      totalChunks: json['totalChunks'] as int,
      data: base64.decode(json['data'] as String),
      checksum: json['checksum'] as String,
    );
  }

  /// Convert chunk to JSON (for wire protocol)
  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'sequenceNumber': sequenceNumber,
      'totalChunks': totalChunks,
      'data': base64.encode(data),
      'checksum': checksum,
    };
  }

  @override
  String toString() {
    return 'MessageChunk(id: $messageId, chunk: $sequenceNumber/$totalChunks, size: ${data.length} bytes)';
  }
}

/// Result of adding a chunk to the reassembly buffer.
class ReassemblyResult {
  /// Whether all chunks have been received and message is complete
  final bool isComplete;

  /// The reassembled data (only if isComplete is true)
  final Uint8List? data;

  /// Set of missing chunk sequence numbers (only if isComplete is false)
  final Set<int> missingChunks;

  const ReassemblyResult({
    required this.isComplete,
    required this.data,
    required this.missingChunks,
  });
}

/// Internal class to track an incomplete reassembly session.
class _ReassemblySession {
  final String messageId;
  final int totalChunks;
  final DateTime startedAt;
  final Map<int, MessageChunk> _receivedChunks = {};

  _ReassemblySession({
    required this.messageId,
    required this.totalChunks,
    required this.startedAt,
  });

  void addChunk(MessageChunk chunk) {
    // Store chunk (overwrites duplicates automatically)
    _receivedChunks[chunk.sequenceNumber] = chunk;
  }

  bool get isComplete => _receivedChunks.length == totalChunks;

  Set<int> getMissingChunks() {
    final missing = <int>{};
    for (var i = 0; i < totalChunks; i++) {
      if (!_receivedChunks.containsKey(i)) {
        missing.add(i);
      }
    }
    return missing;
  }

  Uint8List reassemble() {
    if (!isComplete) {
      throw StateError('Cannot reassemble incomplete message');
    }

    // Calculate total size
    final totalSize = _receivedChunks.values.fold<int>(
      0,
      (sum, chunk) => sum + chunk.data.length,
    );

    // Create buffer and copy chunks in order
    final buffer = Uint8List(totalSize);
    var offset = 0;

    for (var i = 0; i < totalChunks; i++) {
      final chunk = _receivedChunks[i]!;
      buffer.setRange(offset, offset + chunk.data.length, chunk.data);
      offset += chunk.data.length;
    }

    return buffer;
  }
}

/// Exception thrown when chunk checksum verification fails.
class ChunkIntegrityException implements Exception {
  final String message;
  ChunkIntegrityException(this.message);

  @override
  String toString() => 'ChunkIntegrityException: $message';
}

/// Exception thrown when chunk validation fails (wrong total, etc.).
class ChunkValidationException implements Exception {
  final String message;
  ChunkValidationException(this.message);

  @override
  String toString() => 'ChunkValidationException: $message';
}
