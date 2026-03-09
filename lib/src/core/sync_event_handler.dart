import 'sync_item.dart';

/// Callback interface for sync engine lifecycle events.
///
/// Implement this interface to receive notifications about:
/// - Device discovery and connection state
/// - Item synchronization
/// - Sync operations (success/failure)
/// - Diagnostic events
///
/// ## Usage
///
/// ```dart
/// class MySyncEventHandler implements SyncEventHandler {
///   @override
///   void onDevicesChanged(Set<String> deviceIds) {
///     print('Connected devices: ${deviceIds.length}');
///     // Update UI to show device count
///   }
///
///   @override
///   void onConnectionStateChanged(bool isConnected) {
///     print('Network: ${isConnected ? "Online" : "Offline"}');
///     // Show/hide offline indicator
///   }
///
///   @override
///   void onItemReceived(SyncItem item) {
///     print('Received: ${item.syncId}');
///     // Trigger UI refresh
///   }
///
///   @override
///   void onSyncCompleted(int itemsReceived) {
///     print('Sync complete: $itemsReceived items');
///     // Hide loading spinner
///   }
///
///   @override
///   void onSyncFailed(String reason) {
///     print('Sync failed: $reason');
///     // Show error message
///   }
///
///   @override
///   void onSyncEvent(String event, String message) {
///     print('[$event] $message');
///     // Log for debugging
///   }
/// }
/// ```
///
/// ## Thread Safety
///
/// All callbacks may be invoked from background threads or isolates.
/// If you need to update UI, use appropriate mechanisms:
///
/// **Flutter:**
/// ```dart
/// @override
/// void onItemReceived(SyncItem item) {
///   WidgetsBinding.instance.addPostFrameCallback((_) {
///     // Safe to update UI here
///     setState(() {
///       _items.add(item);
///     });
///   });
/// }
/// ```
///
/// **Or use streams:**
/// ```dart
/// class MySyncEventHandler implements SyncEventHandler {
///   final _itemsController = StreamController<SyncItem>.broadcast();
///   Stream<SyncItem> get itemsReceived => _itemsController.stream;
///
///   @override
///   void onItemReceived(SyncItem item) {
///     _itemsController.add(item);
///   }
/// }
/// ```
///
/// ## Event Frequency
///
/// - [onDevicesChanged]: When peers connect/disconnect (1-10 times/min)
/// - [onConnectionStateChanged]: When network state changes (rare)
/// - [onItemReceived]: For each item received (potentially hundreds/sec during sync)
/// - [onSyncCompleted]: After each sync operation (every 30s typical)
/// - [onSyncFailed]: When sync errors occur (rare)
/// - [onSyncEvent]: Diagnostic events (variable, can be verbose)
abstract class SyncEventHandler {
  /// Called when the list of connected peer devices changes.
  ///
  /// This is invoked when:
  /// - A new device is discovered on the network
  /// - A device goes offline (timeout)
  /// - The network is reset
  ///
  /// The [deviceIds] set contains the IDs of all currently connected peers
  /// (excluding this device itself).
  ///
  /// **Typical Use Cases:**
  /// - Update "X devices connected" badge
  /// - Show list of active peers
  /// - Enable/disable sync features based on peer availability
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void onDevicesChanged(Set<String> deviceIds) {
  ///   if (deviceIds.isEmpty) {
  ///     showWarning('No other devices found on network');
  ///   } else {
  ///     updateDeviceCount(deviceIds.length);
  ///   }
  /// }
  /// ```
  void onDevicesChanged(Set<String> deviceIds);

  /// Called when the overall network connectivity state changes.
  ///
  /// [isConnected] indicates whether the device is:
  /// - `true`: Connected to WiFi/network and can discover peers
  /// - `false`: Offline or network unavailable
  ///
  /// **Note:** `isConnected = true` doesn't guarantee peers are present,
  /// only that the network is available. Use [onDevicesChanged] to track
  /// actual peer connections.
  ///
  /// **Typical Use Cases:**
  /// - Show/hide offline indicator
  /// - Disable sync UI when offline
  /// - Queue operations for when network returns
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void onConnectionStateChanged(bool isConnected) {
  ///   if (!isConnected) {
  ///     showOfflineBanner();
  ///     pauseSyncOperations();
  ///   } else {
  ///     hideOfflineBanner();
  ///     resumeSyncOperations();
  ///   }
  /// }
  /// ```
  void onConnectionStateChanged(bool isConnected);

  /// Called when an item is received and stored locally.
  ///
  /// This fires after:
  /// 1. Item is received from network
  /// 2. Item is validated and deserialized
  /// 3. Item is successfully upserted to local storage
  ///
  /// **Frequency:** Can be very high during bulk sync operations
  /// (hundreds of calls per second). Avoid expensive operations here.
  ///
  /// **Typical Use Cases:**
  /// - Increment received count in UI
  /// - Trigger specific item-related updates
  /// - Log for debugging
  ///
  /// **Anti-pattern:** Rebuilding entire UI on each call
  /// ```dart
  /// // ❌ DON'T do this
  /// @override
  /// void onItemReceived(SyncItem item) {
  ///   setState(() {}); // Causes hundreds of rebuilds!
  /// }
  ///
  /// // ✅ DO this instead
  /// @override
  /// void onItemReceived(SyncItem item) {
  ///   _receivedCount++;
  ///   // Batch UI updates
  /// }
  /// ```
  void onItemReceived(SyncItem item);

  /// Called when a sync operation completes successfully.
  ///
  /// [itemsReceived] indicates the number of items processed in this
  /// sync operation (may be 0 if already up-to-date).
  ///
  /// This marks the end of a sync cycle and is a good time to:
  /// - Update UI with final counts
  /// - Hide loading indicators
  /// - Trigger dependent operations
  /// - Log completion metrics
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void onSyncCompleted(int itemsReceived) {
  ///   hideLoadingSpinner();
  ///   if (itemsReceived > 0) {
  ///     showToast('Synced $itemsReceived new items');
  ///   }
  ///   lastSyncTime = DateTime.now();
  /// }
  /// ```
  void onSyncCompleted(int itemsReceived);

  /// Called when a sync operation fails.
  ///
  /// [reason] provides a human-readable description of why the sync failed.
  /// Common reasons:
  /// - `"Network timeout"`
  /// - `"No peers available"`
  /// - `"Checksum mismatch"`
  /// - `"Storage error"`
  ///
  /// **Typical Use Cases:**
  /// - Display error messages to user
  /// - Log errors for diagnostics
  /// - Trigger retry logic
  /// - Report to analytics
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void onSyncFailed(String reason) {
  ///   logger.error('Sync failed: $reason');
  ///
  ///   // Show user-friendly message
  ///   if (reason.contains('timeout')) {
  ///     showError('Sync timeout. Check your network.');
  ///   } else if (reason.contains('No peers')) {
  ///     showInfo('No other devices found.');
  ///   } else {
  ///     showError('Sync failed. Please try again.');
  ///   }
  /// }
  /// ```
  void onSyncFailed(String reason);

  /// Called for diagnostic and debugging events.
  ///
  /// This provides detailed information about internal sync operations
  /// and is primarily useful for:
  /// - Development debugging
  /// - Production diagnostics
  /// - Analytics tracking
  ///
  /// **Event Types:**
  /// - `"sync-started"` - Sync operation initiated
  /// - `"peer-discovered"` - New peer found
  /// - `"chunk-received"` - Data chunk processed
  /// - `"checksum-verified"` - Integrity check passed
  /// - `"http-sync-success"` - HTTP bulk sync completed
  ///
  /// **Note:** This can be very verbose. Consider:
  /// - Filtering events by type
  /// - Only logging in debug builds
  /// - Aggregating instead of logging each event
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void onSyncEvent(String event, String message) {
  ///   // Only log interesting events in production
  ///   if (event.contains('failed') || event.contains('error')) {
  ///     logger.warning('[$event] $message');
  ///   } else if (kDebugMode) {
  ///     print('[$event] $message');
  ///   }
  /// }
  /// ```
  void onSyncEvent(String event, String message);
}
