/// Offline-first multi-device synchronization on local area networks (LAN).
///
/// This library provides peer-to-peer data synchronization between devices
/// on the same local network, without requiring a central server or internet.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:lan_sync_core/lan_sync_core.dart';
///
/// // 1. Define your sync item
/// class Task implements SyncItem {
///   // Implement required fields and methods
/// }
///
/// // 2. Implement storage adapter
/// class TaskStorage implements SyncStorageAdapter<Task> {
///   // Implement storage methods
/// }
///
/// // 3. Implement serializer
/// class TaskSerializer implements SyncSerializer<Task> {
///   // Implement JSON conversion
/// }
///
/// // 4. Implement event handler
/// class MyEventHandler implements SyncEventHandler {
///   // Handle sync events
/// }
///
/// // 5. Initialize sync engine (coming in next phase)
/// // final engine = SyncEngine<Task>(...);
/// // await engine.start();
/// ```
///
/// ## Core Abstractions
///
/// This library is built around clean abstractions that you implement:
///
/// - [SyncItem] - Your domain object that will be synchronized
/// - [SyncStorageAdapter] - Your database integration
/// - [SyncSerializer] - Your JSON serialization logic
/// - [SyncEventHandler] - Your event handling callbacks
/// - [DeviceIdentityProvider] - Your device identification strategy
///
/// ## Package Status
///
/// **v0.1.0-dev** - Core interfaces defined, sync engine implementation in progress.
library;

// Core abstractions
export 'src/core/sync_item.dart';
export 'src/core/sync_storage_adapter.dart';
export 'src/core/sync_serializer.dart';
export 'src/core/sync_event_handler.dart';
export 'src/core/device_identity_provider.dart';
export 'src/core/op_log.dart';
export 'src/core/sync_config.dart';

// Protocol layer
export 'src/network/message_type.dart';
export 'src/network/message_envelope.dart';
export 'src/network/message_protocol.dart';

// Sync engine and transport layer will be exported as they're implemented
