import 'dart:convert';
import 'dart:io';

import 'package:synchronized/synchronized.dart';

import '../core/device_identity_provider.dart';
import '../core/op_log.dart';

/// File-based operation log using NDJSON format.
///
/// Stores all sync operations in an append-only log file.
/// Each line is a JSON object representing one operation.
///
/// Features:
/// - Thread-safe writes (synchronized)
/// - Fast cursor-based reads
/// - Optional compaction to limit file size
/// - Crash-safe (each line is atomic)
///
/// File format (NDJSON):
/// ```
/// {"opId":"1","timestamp":1234567890,"entity":"task","opType":"create","payload":{...},"sourceDeviceId":"dev-1","logIndex":1}
/// {"opId":"2","timestamp":1234567891,"entity":"task","opType":"update","payload":{...},"sourceDeviceId":"dev-1","logIndex":2}
/// {"opId":"3","timestamp":1234567892,"entity":"task","opType":"delete","payload":{...},"sourceDeviceId":"dev-2","logIndex":3}
/// ```
///
/// Example:
/// ```dart
/// final opLog = FileOpLog(
///   filePath: '/path/to/oplog.ndjson',
///   deviceIdentity: deviceIdentity,
/// );
///
/// await opLog.initialize();
///
/// // Append operation
/// final entry = await opLog.appendLocalOp(
///   entity: 'task',
///   opType: 'create',
///   payload: {'id': '1', 'title': 'Task 1'},
/// );
///
/// // Read operations since cursor
/// final ops = await opLog.getOpsSince(0);
/// ```
class FileOpLog implements OpLogAdapter {
  /// Path to the NDJSON log file
  final String filePath;

  /// Device identity provider
  final DeviceIdentityProvider deviceIdentity;

  /// How many entries to keep during compaction
  final int compactionKeepLast;

  /// Current log index (monotonically increasing)
  int _currentIndex = 0;

  /// File handle for append operations
  RandomAccessFile? _fileHandle;

  /// Lock for thread-safe writes
  final _writeLock = Lock();

  /// Cache of device ID
  String? _deviceId;

  /// Whether the log has been initialized
  bool _initialized = false;

  FileOpLog({
    required this.filePath,
    required this.deviceIdentity,
    this.compactionKeepLast = 10000,
  });

  /// Initialize the operation log.
  ///
  /// Must be called before any other operations.
  /// Loads the log and determines the current index.
  Future<void> initialize() async {
    if (_initialized) return;

    // Load device ID
    _deviceId = await deviceIdentity.getDeviceId();

    // Create parent directories
    final file = File(filePath);
    await file.parent.create(recursive: true);

    // Open file for appending
    _fileHandle = await file.open(mode: FileMode.append);

    // Determine current index from existing entries
    await _loadCurrentIndex();

    _initialized = true;
  }

  @override
  Future<OpLogEntry> appendLocalOp({
    required String entity,
    required String opType,
    required Map<String, dynamic> payload,
    String? sourceDeviceId,
  }) async {
    _ensureInitialized();

    return await _writeLock.synchronized(() async {
      // Increment index
      _currentIndex++;

      // Create entry
      final entry = OpLogEntry(
        opId: _generateOpId(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        entity: entity,
        opType: opType,
        payload: payload,
        sourceDeviceId: sourceDeviceId ?? _deviceId!,
        logIndex: _currentIndex,
      );

      // Append to file
      await _appendToFile(entry);

      return entry;
    });
  }

  @override
  Future<OpLogEntry?> recordExternalOp(OpLogEntry entry) async {
    _ensureInitialized();

    return await _writeLock.synchronized(() async {
      // Check if operation already exists (deduplication)
      final existing = await _findOpByOpId(entry.opId);
      if (existing != null) {
        return null; // Already recorded
      }

      // Increment index
      _currentIndex++;

      // Create new entry with our log index
      final newEntry = OpLogEntry(
        opId: entry.opId,
        timestamp: entry.timestamp,
        entity: entry.entity,
        opType: entry.opType,
        payload: entry.payload,
        sourceDeviceId: entry.sourceDeviceId,
        logIndex: _currentIndex,
      );

      // Append to file
      await _appendToFile(newEntry);

      return newEntry;
    });
  }

  @override
  Future<List<OpLogEntry>> getOpsSince(
    int sinceCursor, {
    int limit = 1000,
  }) async {
    _ensureInitialized();

    final file = File(filePath);

    if (!await file.exists()) {
      return [];
    }

    final lines = await file.readAsLines();
    final ops = <OpLogEntry>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final entry = OpLogEntry.fromJson(json);

        // Include operations after the cursor
        final index = entry.logIndex ?? 0;
        if (index > sinceCursor) {
          ops.add(entry);

          // Stop if we've reached the limit
          if (ops.length >= limit) {
            break;
          }
        }
      } catch (e) {
        // Skip corrupted lines
        continue;
      }
    }

    return ops;
  }

  @override
  Future<Map<String, OpLogEntry>> findOpsForSyncIds(
    Iterable<String> syncIds,
  ) async {
    _ensureInitialized();

    final result = <String, OpLogEntry>{};
    final syncIdSet = Set<String>.from(syncIds);

    final file = File(filePath);
    if (!await file.exists()) {
      return result;
    }

    final lines = await file.readAsLines();

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final entry = OpLogEntry.fromJson(json);

        // Check if payload contains a sync ID we're looking for
        final itemId = entry.payload['id'] as String?;
        if (itemId != null && syncIdSet.contains(itemId)) {
          result[itemId] = entry;
        }
      } catch (e) {
        // Skip corrupted lines
        continue;
      }
    }

    return result;
  }

  @override
  Future<void> init() async {
    await initialize();
  }

  @override
  Future<void> advanceTo(int cursor) async {
    _ensureInitialized();

    await _writeLock.synchronized(() async {
      if (cursor > _currentIndex) {
        _currentIndex = cursor;
      }
    });
  }

  @override
  int get lastOpId => _currentIndex;

  /// Compact the log by keeping only recent entries.
  ///
  /// Removes old entries to prevent the file from growing indefinitely.
  /// Keeps the last [compactionKeepLast] entries.
  ///
  /// Should be called periodically (e.g., once per day).
  Future<void> compact() async {
    _ensureInitialized();

    await _writeLock.synchronized(() async {
      final allOps = await getOpsSince(0);

      if (allOps.length <= compactionKeepLast) {
        return; // No compaction needed
      }

      // Keep only recent entries
      final toKeep = allOps.skip(allOps.length - compactionKeepLast);

      // Close current file handle
      await _fileHandle?.close();
      _fileHandle = null;

      // Rewrite file with kept entries
      final file = File(filePath);
      final tempFile = File('$filePath.tmp');

      // Write to temp file
      final sink = tempFile.openWrite();
      for (final entry in toKeep) {
        sink.writeln(jsonEncode(entry.toJson()));
      }
      await sink.flush();
      await sink.close();

      // Replace original with temp
      await tempFile.rename(filePath);

      // Reopen file handle
      _fileHandle = await file.open(mode: FileMode.append);

      // Update current index
      if (toKeep.isNotEmpty) {
        _currentIndex = toKeep.last.logIndex ?? 0;
      }
    });
  }

  /// Close the operation log.
  ///
  /// Closes the file handle and releases resources.
  Future<void> close() async {
    await _fileHandle?.close();
    _fileHandle = null;
    _initialized = false;
  }

  /// Find an operation by its operation ID
  Future<OpLogEntry?> _findOpByOpId(String opId) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }

    final lines = await file.readAsLines();

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final entry = OpLogEntry.fromJson(json);

        if (entry.opId == opId) {
          return entry;
        }
      } catch (e) {
        // Skip corrupted lines
        continue;
      }
    }

    return null;
  }

  /// Load the current index from existing log entries
  Future<void> _loadCurrentIndex() async {
    final file = File(filePath);

    if (!await file.exists()) {
      _currentIndex = 0;
      return;
    }

    try {
      final lines = await file.readAsLines();

      if (lines.isEmpty) {
        _currentIndex = 0;
        return;
      }

      // Find max log index
      var maxIndex = 0;
      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final index = json['logIndex'] as int? ?? 0;
          if (index > maxIndex) {
            maxIndex = index;
          }
        } catch (e) {
          // Skip corrupted lines
          continue;
        }
      }

      _currentIndex = maxIndex;
    } catch (e) {
      // File read error - start from 0
      _currentIndex = 0;
    }
  }

  /// Append an entry to the log file
  Future<void> _appendToFile(OpLogEntry entry) async {
    final json = jsonEncode(entry.toJson());
    await _fileHandle!.writeString('$json\n');
    await _fileHandle!.flush();
  }

  /// Generate a unique operation ID
  String _generateOpId() {
    // OpId format: deviceId-logIndex-timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${_deviceId!.substring(0, 8)}-$_currentIndex-$timestamp';
  }

  /// Ensure the log is initialized
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('FileOpLog not initialized. Call initialize() first.');
    }
  }
}
