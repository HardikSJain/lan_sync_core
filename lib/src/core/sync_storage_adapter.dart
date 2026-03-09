import 'sync_item.dart';

/// Storage backend adapter for persisting synchronized items.
///
/// This interface decouples the sync engine from any specific database
/// implementation. Users must implement this to integrate their chosen
/// storage solution (ObjectBox, Hive, SQLite, Isar, etc.).
///
/// ## Responsibilities
///
/// The adapter is responsible for:
/// - **CRUD operations** on [SyncItem] instances
/// - **Batch operations** for efficient bulk sync
/// - **Querying** by syncId and other criteria
/// - **Conflict resolution** (last-write-wins based on updatedAt)
///
/// ## Thread Safety
///
/// Implementations should be thread-safe as they may be called from
/// multiple isolates or async contexts simultaneously.
///
/// ## Example Implementation (ObjectBox)
///
/// ```dart
/// class ObjectBoxSyncAdapter implements SyncStorageAdapter<Task> {
///   final Box<Task> _box;
///
///   ObjectBoxSyncAdapter(this._box);
///
///   @override
///   Future<List<Task>> getAllItems() async {
///     return _box.getAll();
///   }
///
///   @override
///   Future<Task?> getItemBySyncId(String syncId) async {
///     final query = _box.query(Task_.syncId.equals(syncId)).build();
///     final result = query.findFirst();
///     query.close();
///     return result;
///   }
///
///   @override
///   Future<bool> upsertItem(Task item) async {
///     final existing = await getItemBySyncId(item.syncId);
///     if (existing != null) {
///       // Last-write-wins: only update if newer
///       if (item.updatedAt.isAfter(existing.updatedAt)) {
///         _box.put(item);
///         return false; // updated existing
///       }
///       return false; // ignored stale update
///     }
///     _box.put(item);
///     return true; // created new
///   }
///
///   @override
///   Future<Map<String, int>> batchUpsertItems(List<Task> items) async {
///     int created = 0;
///     int updated = 0;
///
///     for (final item in items) {
///       final isNew = await upsertItem(item);
///       if (isNew) {
///         created++;
///       } else {
///         updated++;
///       }
///     }
///
///     return {'created': created, 'updated': updated};
///   }
///
///   @override
///   Future<int> getItemCount() async {
///     return _box.count();
///   }
///
///   @override
///   Future<List<Task>> getItemsSince(DateTime timestamp) async {
///     final query = _box
///         .query(Task_.updatedAt.greaterThan(timestamp.millisecondsSinceEpoch))
///         .build();
///     final result = query.find();
///     query.close();
///     return result;
///   }
/// }
/// ```
///
/// ## Performance Considerations
///
/// - **Index syncId** for fast lookups
/// - **Index updatedAt** for incremental sync queries
/// - **Batch operations** should be atomic when possible
/// - **Large datasets** (10k+ items) should use pagination in custom methods
abstract class SyncStorageAdapter<T extends SyncItem> {
  /// Retrieves all items from storage.
  ///
  /// This is called during:
  /// - Full sync requests from peers
  /// - Snapshot creation
  /// - Checksum calculation
  ///
  /// **Performance Warning:** For large datasets (10k+ items), consider
  /// implementing pagination or streaming variants in your adapter.
  ///
  /// Returns an empty list if no items exist.
  Future<List<T>> getAllItems();

  /// Retrieves a single item by its unique [syncId].
  ///
  /// This is called during:
  /// - Conflict detection
  /// - Duplicate checking
  /// - Item updates
  ///
  /// Returns `null` if no item with the given [syncId] exists.
  ///
  /// **Implementation Note:** This should use an index on [syncId] for
  /// O(log n) or O(1) lookup performance.
  Future<T?> getItemBySyncId(String syncId);

  /// Inserts or updates an item using last-write-wins conflict resolution.
  ///
  /// The implementation should:
  /// 1. Check if an item with the same [syncId] exists
  /// 2. If it exists:
  ///    - Compare [updatedAt] timestamps
  ///    - Keep the newer version (or current if equal)
  /// 3. If it doesn't exist:
  ///    - Insert as new item
  ///
  /// Returns:
  /// - `true` if a new item was created
  /// - `false` if an existing item was updated or the update was ignored
  ///
  /// **Thread Safety:** Must be atomic to avoid race conditions.
  ///
  /// Example conflict resolution:
  /// ```dart
  /// final existing = await getItemBySyncId(item.syncId);
  /// if (existing != null) {
  ///   if (item.updatedAt.isAfter(existing.updatedAt)) {
  ///     // New version is newer, update
  ///     await _updateInDatabase(item);
  ///     return false;
  ///   }
  ///   // Existing version is newer or equal, ignore
  ///   return false;
  /// }
  /// // No existing item, create new
  /// await _insertInDatabase(item);
  /// return true;
  /// ```
  Future<bool> upsertItem(T item);

  /// Batch insert or update multiple items efficiently.
  ///
  /// This is the primary method used during sync operations and should
  /// be optimized for performance (use transactions, bulk inserts, etc.).
  ///
  /// Returns a map with:
  /// - `'created'`: Number of new items inserted
  /// - `'updated'`: Number of existing items updated
  ///
  /// Example:
  /// ```dart
  /// final result = await adapter.batchUpsertItems(items);
  /// print('Created: ${result['created']}, Updated: ${result['updated']}');
  /// ```
  ///
  /// **Performance Tips:**
  /// - Wrap in a transaction for atomicity
  /// - Use batch insert APIs when available
  /// - Pre-fetch existing items to minimize queries
  /// - Consider parallel processing for very large batches (with care)
  Future<Map<String, int>> batchUpsertItems(List<T> items);

  /// Returns the total number of items in storage.
  ///
  /// Used for:
  /// - UI display (total count badges)
  /// - Checksum verification
  /// - Progress tracking during sync
  ///
  /// Should be O(1) if possible (most databases cache this).
  Future<int> getItemCount();

  /// Retrieves items modified after the given [timestamp].
  ///
  /// This enables incremental sync strategies where only changed items
  /// are transmitted.
  ///
  /// Returns items where `updatedAt > timestamp`, sorted by [updatedAt].
  ///
  /// **Implementation Note:** Requires an index on [updatedAt] for
  /// efficient querying.
  ///
  /// Example:
  /// ```dart
  /// // Get items changed in the last hour
  /// final recentChanges = await adapter.getItemsSince(
  ///   DateTime.now().subtract(Duration(hours: 1))
  /// );
  /// ```
  Future<List<T>> getItemsSince(DateTime timestamp);
}
