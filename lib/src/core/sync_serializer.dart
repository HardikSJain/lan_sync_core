import 'sync_item.dart';

/// Handles serialization and deserialization of [SyncItem] instances.
///
/// This interface separates the concerns of network protocol (message
/// structure) from domain object structure, allowing users to customize
/// how their items are encoded for transmission.
///
/// ## Responsibilities
///
/// - Convert [SyncItem] to/from JSON for network transmission
/// - Handle lists of items with optional operation metadata
/// - Ensure wire format compatibility across versions
///
/// ## Example Implementation
///
/// ```dart
/// class TaskSerializer implements SyncSerializer<Task> {
///   @override
///   Map<String, dynamic> itemToJson(Task item) {
///     return item.toJson();
///   }
///
///   @override
///   Task itemFromJson(Map<String, dynamic> json) {
///     return Task.fromJson(json);
///   }
///
///   @override
///   List<Map<String, dynamic>> encodeItemList(List<Task> items) {
///     return items.map((item) => {
///       'item': itemToJson(item),
///       // Optional: add metadata
///       'metadata': {
///         'version': '1.0',
///         'timestamp': DateTime.now().toIso8601String(),
///       },
///     }).toList();
///   }
///
///   @override
///   List<Task> decodeItemList(List<dynamic> jsonList) {
///     return jsonList.map((entry) {
///       if (entry is Map) {
///         // Handle both wrapped and unwrapped formats
///         final itemJson = entry['item'] ?? entry;
///         if (itemJson is Map<String, dynamic>) {
///           return itemFromJson(itemJson);
///         }
///       }
///       throw FormatException('Invalid item format in list');
///     }).toList();
///   }
/// }
/// ```
///
/// ## Wire Format Considerations
///
/// ### Backward Compatibility
/// - New fields should be optional with defaults
/// - Don't remove fields without version migration
/// - Consider adding a format version field
///
/// ### Efficiency
/// - Avoid redundant data in each list item
/// - Use compact field names for large datasets
/// - Consider compression for very large payloads (handled by transport layer)
///
/// ### Validation
/// - Validate required fields during deserialization
/// - Provide helpful error messages for debugging
/// - Handle missing/malformed data gracefully
abstract class SyncSerializer<T extends SyncItem> {
  /// Serializes a single item to JSON.
  ///
  /// The returned map should:
  /// - Include all fields from [SyncItem.toJson]
  /// - Be valid JSON (primitives, maps, lists only)
  /// - Be deserializable by [itemFromJson]
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Map<String, dynamic> itemToJson(Task item) {
  ///   return {
  ///     'syncId': item.syncId,
  ///     'createdAt': item.createdAt.toIso8601String(),
  ///     'updatedAt': item.updatedAt.toIso8601String(),
  ///     'sourceDeviceId': item.sourceDeviceId,
  ///     'title': item.title,
  ///     'completed': item.completed,
  ///   };
  /// }
  /// ```
  Map<String, dynamic> itemToJson(T item);

  /// Deserializes a single item from JSON.
  ///
  /// The implementation should:
  /// - Parse all required fields
  /// - Validate data types
  /// - Provide defaults for optional fields
  /// - Throw [FormatException] for invalid data
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Task itemFromJson(Map<String, dynamic> json) {
  ///   return Task(
  ///     syncId: json['syncId'] as String,
  ///     createdAt: DateTime.parse(json['createdAt'] as String),
  ///     updatedAt: DateTime.parse(json['updatedAt'] as String),
  ///     sourceDeviceId: json['sourceDeviceId'] as String,
  ///     title: json['title'] as String,
  ///     completed: json['completed'] as bool? ?? false,
  ///   );
  /// }
  /// ```
  ///
  /// Throws [FormatException] if the JSON is invalid.
  T itemFromJson(Map<String, dynamic> json);

  /// Encodes a list of items for network transmission.
  ///
  /// The default behavior can simply map over items:
  /// ```dart
  /// @override
  /// List<Map<String, dynamic>> encodeItemList(List<T> items) {
  ///   return items.map(itemToJson).toList();
  /// }
  /// ```
  ///
  /// For advanced use cases, you might wrap items with metadata:
  /// ```dart
  /// @override
  /// List<Map<String, dynamic>> encodeItemList(List<T> items) {
  ///   return items.map((item) => {
  ///     'item': itemToJson(item),
  ///     'checksum': _calculateChecksum(item),
  ///     'version': '1.0',
  ///   }).toList();
  /// }
  /// ```
  ///
  /// **Note:** The sync engine may add additional metadata (operation IDs,
  /// log indices) when transmitting. This method handles domain-level
  /// serialization only.
  List<Map<String, dynamic>> encodeItemList(List<T> items);

  /// Decodes a list of items received from the network.
  ///
  /// Should handle both:
  /// - Plain item arrays: `[{item1}, {item2}]`
  /// - Wrapped items: `[{item: {item1}}, {item: {item2}}]`
  ///
  /// Example with error handling:
  /// ```dart
  /// @override
  /// List<T> decodeItemList(List<dynamic> jsonList) {
  ///   final items = <T>[];
  ///
  ///   for (int i = 0; i < jsonList.length; i++) {
  ///     try {
  ///       final entry = jsonList[i];
  ///       if (entry is Map<String, dynamic>) {
  ///         // Try wrapped format first
  ///         final itemJson = entry['item'] ?? entry;
  ///         if (itemJson is Map<String, dynamic>) {
  ///           items.add(itemFromJson(itemJson));
  ///           continue;
  ///         }
  ///       }
  ///       print('Warning: Skipping invalid item at index $i');
  ///     } catch (e) {
  ///       print('Error decoding item at index $i: $e');
  ///       // Continue processing remaining items
  ///     }
  ///   }
  ///
  ///   return items;
  /// }
  /// ```
  ///
  /// **Resilience:** Should be tolerant of partially malformed data,
  /// skipping invalid items rather than failing the entire batch.
  List<T> decodeItemList(List<dynamic> jsonList);
}
