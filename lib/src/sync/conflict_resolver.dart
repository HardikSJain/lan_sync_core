import 'package:collection/collection.dart';

import '../core/sync_item.dart';

/// Resolves conflicts when the same item is updated on multiple devices.
///
/// Conflicts occur when:
/// - Same item (by syncId) exists on both devices
/// - Items have different content
/// - Items were updated at different times (or same time on different devices)
///
/// Example:
/// ```dart
/// final resolver = LastWriteWinsResolver<Task>();
///
/// final local = Task(id: '1', title: 'Local', updatedAt: DateTime(2026, 3, 26, 10, 0));
/// final remote = Task(id: '1', title: 'Remote', updatedAt: DateTime(2026, 3, 26, 10, 5));
///
/// final winner = resolver.resolve(local, remote);
/// // winner == remote (newer timestamp)
/// ```
abstract class ConflictResolver<T extends SyncItem> {
  /// Resolve conflict between local and remote versions of an item.
  ///
  /// Returns the version that should be kept.
  T resolve(T local, T remote);

  /// Check if two items are in conflict.
  ///
  /// Items conflict when they have the same ID but different content.
  bool hasConflict(T local, T remote) {
    // Same item ID
    if (local.syncId != remote.syncId) return false;

    // Different content
    if (areEqual(local, remote)) return false;

    // Not at exact same timestamp (if same timestamp, not really a conflict)
    return !local.updatedAt.isAtSameMomentAs(remote.updatedAt);
  }

  /// Deep equality check via JSON serialization.
  ///
  /// Public so subclasses can use it.
  bool areEqual(T a, T b) {
    return const DeepCollectionEquality().equals(a.toJson(), b.toJson());
  }
}

/// Last-Write-Wins conflict resolution strategy.
///
/// Resolves conflicts by choosing the item with the most recent timestamp.
/// If timestamps are identical, uses device ID lexicographic comparison
/// as a deterministic tiebreaker.
///
/// This is the default strategy and works well for most use cases where
/// recency is the primary concern.
///
/// Example:
/// ```dart
/// final resolver = LastWriteWinsResolver<Task>();
///
/// // Remote is newer -> remote wins
/// final winner1 = resolver.resolve(
///   Task(updatedAt: DateTime(2026, 3, 26, 10, 0)),
///   Task(updatedAt: DateTime(2026, 3, 26, 10, 5)),
/// );
///
/// // Same timestamp -> device ID tiebreaker
/// final winner2 = resolver.resolve(
///   Task(updatedAt: DateTime(2026, 3, 26, 10, 0), sourceDeviceId: 'dev-a'),
///   Task(updatedAt: DateTime(2026, 3, 26, 10, 0), sourceDeviceId: 'dev-b'),
/// );
/// // winner2 depends on lexicographic comparison of device IDs
/// ```
class LastWriteWinsResolver<T extends SyncItem> extends ConflictResolver<T> {
  @override
  T resolve(T local, T remote) {
    // Compare timestamps
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      return remote; // Remote is newer
    } else if (local.updatedAt.isAfter(remote.updatedAt)) {
      return local; // Local is newer
    } else {
      // Same timestamp - use device ID as deterministic tiebreaker
      // Lexicographically larger device ID wins (arbitrary but consistent)
      return local.sourceDeviceId.compareTo(remote.sourceDeviceId) > 0
          ? local
          : remote;
    }
  }
}

/// Custom conflict resolution strategy.
///
/// Allows users to define their own conflict resolution logic.
///
/// Example:
/// ```dart
/// // Always prefer local
/// final resolver = CustomConflictResolver<Task>(
///   (local, remote) => local,
/// );
///
/// // Prefer items with more content
/// final resolver2 = CustomConflictResolver<Task>(
///   (local, remote) {
///     final localLength = local.title.length;
///     final remoteLength = remote.title.length;
///     return localLength > remoteLength ? local : remote;
///   },
/// );
/// ```
class CustomConflictResolver<T extends SyncItem> extends ConflictResolver<T> {
  /// Custom resolution function provided by user
  final T Function(T local, T remote) resolveFunction;

  CustomConflictResolver(this.resolveFunction);

  @override
  T resolve(T local, T remote) => resolveFunction(local, remote);
}

/// Logs conflict resolution decisions for debugging and auditing.
///
/// Useful for understanding why certain versions were chosen during sync.
class ConflictLog {
  /// ID of the item that had a conflict
  final String itemId;

  /// When the conflict was detected
  final DateTime detectedAt;

  /// Local version (as JSON)
  final Map<String, dynamic> localVersion;

  /// Remote version (as JSON)
  final Map<String, dynamic> remoteVersion;

  /// Which version won ('local' or 'remote')
  final String resolution;

  /// Human-readable reason for the resolution
  final String reason;

  const ConflictLog({
    required this.itemId,
    required this.detectedAt,
    required this.localVersion,
    required this.remoteVersion,
    required this.resolution,
    required this.reason,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'detectedAt': detectedAt.toIso8601String(),
      'localVersion': localVersion,
      'remoteVersion': remoteVersion,
      'resolution': resolution,
      'reason': reason,
    };
  }

  /// Create from JSON
  factory ConflictLog.fromJson(Map<String, dynamic> json) {
    return ConflictLog(
      itemId: json['itemId'] as String,
      detectedAt: DateTime.parse(json['detectedAt'] as String),
      localVersion: Map<String, dynamic>.from(json['localVersion'] as Map),
      remoteVersion: Map<String, dynamic>.from(json['remoteVersion'] as Map),
      resolution: json['resolution'] as String,
      reason: json['reason'] as String,
    );
  }

  @override
  String toString() {
    return '''
ConflictLog:
  Item: $itemId
  Time: $detectedAt
  Resolution: $resolution ($reason)
  Local: $localVersion
  Remote: $remoteVersion
''';
  }
}
