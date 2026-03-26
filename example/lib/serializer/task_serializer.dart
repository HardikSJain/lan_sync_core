import 'package:lan_sync_core/lan_sync_core.dart';
import '../models/task.dart';

/// Serializer for Task objects
class TaskSerializer implements SyncSerializer<Task> {
  const TaskSerializer();

  @override
  Map<String, dynamic> itemToJson(Task item) {
    return item.toJson();
  }

  @override
  Task itemFromJson(Map<String, dynamic> json) {
    return Task.fromJson(json);
  }

  @override
  List<Map<String, dynamic>> encodeItemList(List<Task> items) {
    return items.map((item) => itemToJson(item)).toList();
  }

  @override
  List<Task> decodeItemList(List<dynamic> jsonList) {
    final tasks = <Task>[];

    for (int i = 0; i < jsonList.length; i++) {
      try {
        final entry = jsonList[i];
        if (entry is Map<String, dynamic>) {
          // Try wrapped format first
          final itemJson = entry['item'] ?? entry;
          if (itemJson is Map<String, dynamic>) {
            tasks.add(itemFromJson(itemJson));
            continue;
          }
        }
        // Skip invalid items
      } catch (e) {
        // Skip and continue
        continue;
      }
    }

    return tasks;
  }
}
