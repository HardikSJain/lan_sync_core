import 'package:lan_sync_core/lan_sync_core.dart';
import '../models/task.dart';

/// In-memory storage adapter for tasks
/// 
/// In a real app, use ObjectBox, Hive, SQLite, or Isar
class TaskStorage implements SyncStorageAdapter<Task> {
  final Map<String, Task> _tasks = {};

  /// Stream controller for real-time updates
  final _updateController = Stream<void>.periodic(
    const Duration(milliseconds: 100),
  ).asBroadcastStream();

  Stream<void> get updates => _updateController;

  @override
  Future<List<Task>> getAllItems() async {
    return _tasks.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<Task?> getItemBySyncId(String syncId) async {
    return _tasks[syncId];
  }

  @override
  Future<bool> upsertItem(Task item) async {
    final exists = _tasks.containsKey(item.syncId);
    
    if (exists) {
      final existing = _tasks[item.syncId]!;
      // Last-write-wins: only update if newer
      if (item.updatedAt.isAfter(existing.updatedAt)) {
        _tasks[item.syncId] = item;
        return false; // Updated
      }
      return false; // Skipped (older)
    } else {
      _tasks[item.syncId] = item;
      return true; // Inserted
    }
  }

  @override
  Future<Map<String, int>> batchUpsertItems(List<Task> items) async {
    var inserted = 0;
    var updated = 0;

    for (final item in items) {
      final wasInserted = await upsertItem(item);
      if (wasInserted) {
        inserted++;
      } else {
        updated++;
      }
    }

    return {'inserted': inserted, 'updated': updated};
  }

  @override
  Future<int> getItemCount() async {
    return _tasks.length;
  }

  @override
  Future<List<Task>> getItemsSince(DateTime timestamp) async {
    return _tasks.values
        .where((task) => task.updatedAt.isAfter(timestamp))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Delete a task (local only, not part of sync)
  Future<void> deleteTask(String syncId) async {
    _tasks.remove(syncId);
  }

  /// Clear all tasks
  Future<void> clear() async {
    _tasks.clear();
  }
}
