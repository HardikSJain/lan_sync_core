/// Represents an item that can be synchronized across devices in a LAN.
///
/// This is the fundamental abstraction that users must implement for their
/// domain objects. Each [SyncItem] must have:
/// - A unique identifier ([syncId]) that remains stable across devices
/// - Creation and modification timestamps for conflict resolution
/// - Source device tracking for operation log coordination
/// - JSON serialization for network transmission
///
/// ## Example Implementation
///
/// ```dart
/// class Task implements SyncItem {
///   @override
///   final String syncId;
///
///   @override
///   final DateTime createdAt;
///
///   @override
///   final DateTime updatedAt;
///
///   @override
///   final String sourceDeviceId;
///
///   final String title;
///   final bool completed;
///
///   Task({
///     required this.syncId,
///     required this.createdAt,
///     required this.updatedAt,
///     required this.sourceDeviceId,
///     required this.title,
///     required this.completed,
///   });
///
///   @override
///   Map<String, dynamic> toJson() => {
///     'syncId': syncId,
///     'createdAt': createdAt.toIso8601String(),
///     'updatedAt': updatedAt.toIso8601String(),
///     'sourceDeviceId': sourceDeviceId,
///     'title': title,
///     'completed': completed,
///   };
///
///   factory Task.fromJson(Map<String, dynamic> json) => Task(
///     syncId: json['syncId'] as String,
///     createdAt: DateTime.parse(json['createdAt'] as String),
///     updatedAt: DateTime.parse(json['updatedAt'] as String),
///     sourceDeviceId: json['sourceDeviceId'] as String,
///     title: json['title'] as String,
///     completed: json['completed'] as bool,
///   );
/// }
/// ```
///
/// ## Best Practices
///
/// ### Unique Identifiers
/// - Use UUIDs or timestamp-based IDs for [syncId]
/// - Ensure [syncId] is globally unique (not just device-unique)
/// - Never reuse [syncId] values
///
/// ### Timestamps
/// - [createdAt] should never change after creation
/// - [updatedAt] should be set on every modification
/// - Use UTC for consistency across devices
///
/// ### Serialization
/// - [toJson] should include all fields needed for sync
/// - Don't include local-only state (UI state, temp flags)
/// - Keep payloads small (< 10KB per item recommended)
///
/// ### Conflict Resolution
/// - Last-write-wins is based on [updatedAt]
/// - Consider adding version numbers for more control
/// - Use [sourceDeviceId] to track origin
abstract class SyncItem {
  /// Unique identifier for this item, stable across all devices.
  ///
  /// This ID must be:
  /// - Globally unique (UUID v4 recommended)
  /// - Immutable after creation
  /// - Used as the primary key for sync
  ///
  /// Example: `'550e8400-e29b-41d4-a716-446655440000'`
  String get syncId;

  /// Timestamp when this item was first created.
  ///
  /// This should:
  /// - Be set once when the item is created
  /// - Never change after initial creation
  /// - Use UTC timezone for consistency
  ///
  /// Used for:
  /// - Ordering items chronologically
  /// - Debugging sync issues
  /// - Data retention policies
  DateTime get createdAt;

  /// Timestamp when this item was last modified.
  ///
  /// This should:
  /// - Be updated on every modification
  /// - Use UTC timezone for consistency
  /// - Be used for last-write-wins conflict resolution
  ///
  /// Critical for:
  /// - Determining which version is newer
  /// - Sync coordination
  /// - Change detection
  DateTime get updatedAt;

  /// Device ID of the device that originally created this item.
  ///
  /// This should:
  /// - Be set when the item is created
  /// - Never change (even if item is modified on other devices)
  /// - Match the device ID from [DeviceIdentityProvider]
  ///
  /// Used for:
  /// - Operation log tracking
  /// - Debugging data provenance
  /// - Analytics
  String get sourceDeviceId;

  /// Serializes this item to JSON for network transmission.
  ///
  /// The returned map must:
  /// - Include all sync-required fields (syncId, timestamps, etc.)
  /// - Include all domain fields needed to reconstruct the item
  /// - Be serializable to JSON (no custom objects)
  /// - Be deserializable by [SyncSerializer.itemFromJson]
  ///
  /// Example:
  /// ```dart
  /// {
  ///   'syncId': '550e8400-e29b-41d4-a716-446655440000',
  ///   'createdAt': '2026-03-09T10:30:00.000Z',
  ///   'updatedAt': '2026-03-09T11:45:00.000Z',
  ///   'sourceDeviceId': 'device-abc123',
  ///   'title': 'Buy groceries',
  ///   'completed': false
  /// }
  /// ```
  Map<String, dynamic> toJson();
}
