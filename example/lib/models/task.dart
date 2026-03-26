import 'package:lan_sync_core/lan_sync_core.dart';

/// Simple task model for demonstration
class Task extends SyncItem {
  final String title;
  final bool completed;

  Task({
    required super.syncId,
    required super.createdAt,
    required super.updatedAt,
    required super.sourceDeviceId,
    required this.title,
    this.completed = false,
  });

  /// Create a new task with generated ID
  factory Task.create({
    required String title,
    required String deviceId,
    bool completed = false,
  }) {
    final now = DateTime.now();
    return Task(
      syncId: '${now.millisecondsSinceEpoch}-${title.hashCode}',
      createdAt: now,
      updatedAt: now,
      sourceDeviceId: deviceId,
      title: title,
      completed: completed,
    );
  }

  /// Create copy with updated fields
  Task copyWith({
    String? title,
    bool? completed,
    DateTime? updatedAt,
  }) {
    return Task(
      syncId: syncId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      sourceDeviceId: sourceDeviceId,
      title: title ?? this.title,
      completed: completed ?? this.completed,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'title': title,
        'completed': completed,
      };

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      syncId: json['syncId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sourceDeviceId: json['sourceDeviceId'] as String,
      title: json['title'] as String,
      completed: json['completed'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'Task($title, completed: $completed)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          runtimeType == other.runtimeType &&
          syncId == other.syncId;

  @override
  int get hashCode => syncId.hashCode;
}
