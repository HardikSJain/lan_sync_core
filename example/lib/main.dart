import 'package:flutter/material.dart';
import 'package:lan_sync_core/lan_sync_core.dart';

import 'models/task.dart';
import 'screens/tasks_screen.dart';
import 'serializer/task_serializer.dart';
import 'storage/task_storage.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LAN Sync Example',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const SyncInitializer(),
    );
  }
}

/// Initializes the sync engine and shows loading state
class SyncInitializer extends StatefulWidget {
  const SyncInitializer({super.key});

  @override
  State<SyncInitializer> createState() => _SyncInitializerState();
}

class _SyncInitializerState extends State<SyncInitializer> {
  SyncEngine<Task>? _syncEngine;
  TaskStorage? _storage;
  String? _error;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializeSync();
  }

  Future<void> _initializeSync() async {
    try {
      // Create storage
      final storage = TaskStorage();

      // Create event handler
      final eventHandler = _EventHandler();

      // Create sync engine
      final engine = await SyncEngine.create<Task>(
        storage: storage,
        serializer: const TaskSerializer(),
        eventHandler: eventHandler,
        config: const SyncConfig(
          heartbeatInterval: Duration(seconds: 5),
          periodicVerificationInterval: Duration(seconds: 30),
          enableAutoFullSync: true,
        ),
      );

      // Start sync
      await engine.start();

      if (mounted) {
        setState(() {
          _syncEngine = engine;
          _storage = storage;
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isInitializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.black),
              SizedBox(height: 24),
              Text(
                'Initializing sync engine...',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.gray,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                Text(
                  'Failed to initialize',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _isInitializing = true;
                    });
                    _initializeSync();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return TasksScreen(
      storage: _storage!,
      syncEngine: _syncEngine!,
    );
  }

  @override
  void dispose() {
    _syncEngine?.dispose();
    super.dispose();
  }
}

/// Simple event handler implementation
class _EventHandler implements SyncEventHandler {
  @override
  void onDevicesChanged(Set<String> deviceIds) {
    debugPrint('Devices changed: ${deviceIds.length} connected');
  }

  @override
  void onConnectionStateChanged(bool isConnected) {
    debugPrint('Connection state: ${isConnected ? "Online" : "Offline"}');
  }

  @override
  void onItemReceived(SyncItem item) {
    debugPrint('Item received: ${item.syncId}');
  }

  @override
  void onSyncCompleted(int itemsReceived) {
    debugPrint('Sync completed: $itemsReceived items');
  }

  @override
  void onSyncFailed(String reason) {
    debugPrint('Sync failed: $reason');
  }

  @override
  void onSyncEvent(String event, String message) {
    debugPrint('[$event] $message');
  }
}
