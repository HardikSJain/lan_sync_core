import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:synchronized/synchronized.dart';

/// Adapter interface for storing per-peer sync cursors.
///
/// Cursors track the last operation ID synced from each peer,
/// enabling incremental synchronization.
///
/// ## Cursor Semantics
///
/// - Cursor = last operation ID successfully synced from a peer
/// - Next sync requests operations since (cursor + 1)
/// - Cursor 0 = full sync (no operations synced yet)
///
/// ## Thread Safety
///
/// Implementations must be thread-safe as cursors may be
/// updated from multiple async contexts.
abstract class CursorStorageAdapter {
  /// Get the cursor for a specific peer.
  ///
  /// Returns 0 if no cursor exists (indicating full sync needed).
  Future<int> getCursorForPeer(String peerId);

  /// Update the cursor for a specific peer.
  ///
  /// Should be called after successfully applying operations
  /// from that peer.
  Future<void> updateCursorForPeer(String peerId, int cursor);

  /// Get all cursors (peer ID → cursor value).
  ///
  /// Useful for diagnostics and bulk operations.
  Future<Map<String, int>> getAllCursors();

  /// Clear all cursors.
  ///
  /// Forces full sync on next sync operation.
  Future<void> clearCursors();

  /// Dispose of resources.
  Future<void> dispose();
}

/// File-based cursor storage implementation.
///
/// Stores cursors as JSON in a file with synchronized access.
///
/// ## File Format
///
/// ```json
/// {
///   "device-a": 42,
///   "device-b": 108,
///   "device-c": 0
/// }
/// ```
///
/// ## Thread Safety
///
/// Uses `synchronized` package for file locking to ensure
/// concurrent updates don't corrupt the file.
///
/// ## Example
///
/// ```dart
/// final storage = FileCursorStorage('~/.my_app/cursors.json');
/// await storage.load();
///
/// // Get cursor
/// final cursor = await storage.getCursorForPeer('device-a');
///
/// // Update cursor
/// await storage.updateCursorForPeer('device-a', 42);
///
/// // Clear all
/// await storage.clearCursors();
///
/// // Cleanup
/// await storage.dispose();
/// ```
class FileCursorStorage implements CursorStorageAdapter {
  final String filePath;
  final _lock = Lock();
  Map<String, int> _cursors = {};
  bool _loaded = false;

  FileCursorStorage(this.filePath);

  /// Load cursors from file.
  ///
  /// Must be called before first use.
  /// Safe to call multiple times (idempotent).
  Future<void> load() async {
    if (_loaded) return;

    return _lock.synchronized(() async {
      if (_loaded) return; // Double-check inside lock

      try {
        final file = File(filePath);

        if (await file.exists()) {
          final contents = await file.readAsString();
          if (contents.isNotEmpty) {
            final json = jsonDecode(contents) as Map<String, dynamic>;
            _cursors = json.map((key, value) => MapEntry(key, value as int));
          }
        } else {
          // Create parent directory if needed
          final parent = file.parent;
          if (!await parent.exists()) {
            await parent.create(recursive: true);
          }
        }

        _loaded = true;
      } catch (e) {
        // Log error but don't throw - start with empty cursors
        // In production, you'd log this properly
        print('Warning: Failed to load cursors from $filePath: $e');
        _cursors = {};
        _loaded = true;
      }
    });
  }

  @override
  Future<int> getCursorForPeer(String peerId) async {
    await load(); // Ensure loaded
    return _cursors[peerId] ?? 0;
  }

  @override
  Future<void> updateCursorForPeer(String peerId, int cursor) async {
    await load(); // Ensure loaded

    return _lock.synchronized(() async {
      _cursors[peerId] = cursor;
      await _save();
    });
  }

  @override
  Future<Map<String, int>> getAllCursors() async {
    await load(); // Ensure loaded
    return Map.from(_cursors); // Return copy
  }

  @override
  Future<void> clearCursors() async {
    await load(); // Ensure loaded

    return _lock.synchronized(() async {
      _cursors.clear();
      await _save();
    });
  }

  @override
  Future<void> dispose() async {
    // Nothing to dispose for file storage
    // Could add a final save here if needed
  }

  /// Save cursors to file (must be called inside lock).
  Future<void> _save() async {
    try {
      final file = File(filePath);
      final json = jsonEncode(_cursors);
      await file.writeAsString(json);
    } catch (e) {
      // Log error but don't throw - cursor update failures
      // shouldn't crash the sync engine
      print('Warning: Failed to save cursors to $filePath: $e');
    }
  }
}

/// In-memory cursor storage (for testing).
///
/// Stores cursors in memory only - not persisted.
///
/// Useful for:
/// - Testing
/// - Ephemeral sync sessions
/// - Development
///
/// Example:
/// ```dart
/// final storage = MemoryCursorStorage();
///
/// await storage.updateCursorForPeer('device-a', 42);
/// final cursor = await storage.getCursorForPeer('device-a');
/// ```
class MemoryCursorStorage implements CursorStorageAdapter {
  final Map<String, int> _cursors = {};

  @override
  Future<int> getCursorForPeer(String peerId) async {
    return _cursors[peerId] ?? 0;
  }

  @override
  Future<void> updateCursorForPeer(String peerId, int cursor) async {
    _cursors[peerId] = cursor;
  }

  @override
  Future<Map<String, int>> getAllCursors() async {
    return Map.from(_cursors);
  }

  @override
  Future<void> clearCursors() async {
    _cursors.clear();
  }

  @override
  Future<void> dispose() async {
    _cursors.clear();
  }
}
