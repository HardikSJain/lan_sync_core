import 'package:flutter/material.dart';
import 'package:lan_sync_core/lan_sync_core.dart';
import '../models/task.dart';
import '../storage/task_storage.dart';
import '../theme/app_theme.dart';
import 'sync_status_screen.dart';

class TasksScreen extends StatefulWidget {
  final TaskStorage storage;
  final SyncEngine<Task> syncEngine;

  const TasksScreen({
    required this.storage,
    required this.syncEngine,
    super.key,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _controller = TextEditingController();
  List<Task> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    
    // Listen to storage updates
    widget.storage.updates.listen((_) {
      _loadTasks();
    });
  }

  Future<void> _loadTasks() async {
    final tasks = await widget.storage.getAllItems();
    if (mounted) {
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    }
  }

  Future<void> _addTask() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;

    // Use a simple timestamp-based device ID for the example
    final deviceId = 'device-${DateTime.now().millisecondsSinceEpoch % 10000}';
    final task = Task.create(
      title: title,
      deviceId: deviceId,
    );

    await widget.storage.upsertItem(task);
    await widget.syncEngine.broadcastChange(task);

    _controller.clear();
    _loadTasks();
  }

  Future<void> _toggleTask(Task task) async {
    final updated = task.copyWith(completed: !task.completed);
    await widget.storage.upsertItem(updated);
    await widget.syncEngine.broadcastChange(updated);
    _loadTasks();
  }

  Future<void> _deleteTask(Task task) async {
    await widget.storage.deleteTask(task.syncId);
    _loadTasks();
  }

  Future<void> _syncAll() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Syncing with all peers...'),
        duration: Duration(seconds: 1),
      ),
    );
    
    final count = await widget.syncEngine.syncWithAll();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync initiated with $count peers'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          // Sync button
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncAll,
            tooltip: 'Sync with all peers',
          ),
          
          // Status button
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SyncStatusScreen(
                    syncEngine: widget.syncEngine,
                  ),
                ),
              );
            },
            tooltip: 'Sync status',
          ),
        ],
      ),
      
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.black))
          : Column(
              children: [
                // Add task input
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'Add a task',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _addTask(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: FloatingActionButton(
                          onPressed: _addTask,
                          elevation: 0,
                          child: const Icon(Icons.add, size: 24),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Divider(height: 1),
                
                // Task list
                Expanded(
                  child: _tasks.isEmpty
                      ? Center(
                          child: Text(
                            'No tasks yet',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _tasks.length,
                          separatorBuilder: (context, index) => const Divider(
                            height: 1,
                            indent: 56,
                          ),
                          itemBuilder: (context, index) {
                            final task = _tasks[index];
                            return Dismissible(
                              key: Key(task.syncId),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.red.shade50,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                              ),
                              onDismissed: (_) => _deleteTask(task),
                              child: ListTile(
                                leading: Checkbox(
                                  value: task.completed,
                                  onChanged: (_) => _toggleTask(task),
                                ),
                                title: Text(
                                  task.title,
                                  style: TextStyle(
                                    decoration: task.completed
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: task.completed
                                        ? AppTheme.gray
                                        : AppTheme.black,
                                  ),
                                ),
                                subtitle: Text(
                                  'Updated ${_formatTime(task.updatedAt)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inSeconds < 60) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
