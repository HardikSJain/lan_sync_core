import 'package:lan_sync_core/lan_sync_core.dart';

void main() async {
  final storage = InMemoryTaskStorage();
  final serializer = TaskSerializer();
  final events = ConsoleSyncEvents();
  final identity = DemoDeviceIdentityProvider();

  final task = Task(
    syncId: 'task-1',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    sourceDeviceId: await identity.getDeviceId(),
    title: 'Ship lan_sync_core v0.1.0',
    completed: false,
  );

  final isNew = await storage.upsertItem(task);
  final encoded = serializer.itemToJson(task);
  final decoded = serializer.itemFromJson(encoded);

  events.onConnectionStateChanged(true);
  events.onDevicesChanged({'device-demo-peer'});
  events.onItemReceived(decoded);
  events.onSyncCompleted(isNew ? 1 : 0);

  print('Stored items: ${await storage.getItemCount()}');
  print('Serialized payload: $encoded');
}

class Task implements SyncItem {
  Task({
    required this.syncId,
    required this.createdAt,
    required this.updatedAt,
    required this.sourceDeviceId,
    required this.title,
    required this.completed,
  });

  @override
  final String syncId;

  @override
  final DateTime createdAt;

  @override
  final DateTime updatedAt;

  @override
  final String sourceDeviceId;

  final String title;
  final bool completed;

  @override
  Map<String, dynamic> toJson() => {
    'syncId': syncId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'sourceDeviceId': sourceDeviceId,
    'title': title,
    'completed': completed,
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    syncId: json['syncId'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    sourceDeviceId: json['sourceDeviceId'] as String,
    title: json['title'] as String,
    completed: json['completed'] as bool,
  );
}

class TaskSerializer implements SyncSerializer<Task> {
  @override
  List<Task> decodeItemList(List<dynamic> jsonList) {
    return jsonList
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  List<Map<String, dynamic>> encodeItemList(List<Task> items) {
    return items.map(itemToJson).toList();
  }

  @override
  Task itemFromJson(Map<String, dynamic> json) => Task.fromJson(json);

  @override
  Map<String, dynamic> itemToJson(Task item) => item.toJson();
}

class InMemoryTaskStorage implements SyncStorageAdapter<Task> {
  final Map<String, Task> _items = {};

  @override
  Future<Map<String, int>> batchUpsertItems(List<Task> items) async {
    var created = 0;
    var updated = 0;

    for (final item in items) {
      final isNew = await upsertItem(item);
      if (isNew) {
        created++;
      } else {
        updated++;
      }
    }

    return {'created': created, 'updated': updated};
  }

  @override
  Future<List<Task>> getAllItems() async => _items.values.toList();

  @override
  Future<int> getItemCount() async => _items.length;

  @override
  Future<Task?> getItemBySyncId(String syncId) async => _items[syncId];

  @override
  Future<List<Task>> getItemsSince(DateTime timestamp) async {
    return _items.values
        .where((item) => item.updatedAt.isAfter(timestamp))
        .toList();
  }

  @override
  Future<bool> upsertItem(Task item) async {
    final existing = _items[item.syncId];
    if (existing == null) {
      _items[item.syncId] = item;
      return true;
    }

    if (item.updatedAt.isAfter(existing.updatedAt)) {
      _items[item.syncId] = item;
    }
    return false;
  }
}

class ConsoleSyncEvents implements SyncEventHandler {
  @override
  void onConnectionStateChanged(bool isConnected) {
    print('Connection: ${isConnected ? 'online' : 'offline'}');
  }

  @override
  void onDevicesChanged(Set<String> deviceIds) {
    print('Devices: $deviceIds');
  }

  @override
  void onItemReceived(SyncItem item) {
    print('Received item: ${item.syncId}');
  }

  @override
  void onSyncCompleted(int itemsReceived) {
    print('Sync complete: $itemsReceived item(s)');
  }

  @override
  void onSyncEvent(String event, String message) {
    print('[$event] $message');
  }

  @override
  void onSyncFailed(String reason) {
    print('Sync failed: $reason');
  }
}

class DemoDeviceIdentityProvider implements DeviceIdentityProvider {
  @override
  Future<String> getDeviceId() async => 'device-demo-local';

  @override
  Future<String?> getDeviceName() async => 'Demo Device';
}
