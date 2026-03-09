/// Provides stable device identity for sync coordination.
///
/// The device identity is used to:
/// - Uniquely identify this device in the sync mesh
/// - Track which device created each item
/// - Generate monotonic operation IDs
/// - Prevent self-messaging in broadcast scenarios
///
/// ## Requirements
///
/// The device ID must be:
/// - **Stable** across app restarts
/// - **Unique** within the sync network (collision chance < 1 in 1 billion)
/// - **Readable** for debugging (avoid binary/hex strings if possible)
///
/// ## Default Implementation
///
/// The package provides a default file-based implementation that:
/// - Generates a random ID on first run
/// - Persists it to local storage
/// - Reuses the same ID on subsequent runs
///
/// ## Custom Implementation
///
/// You might want a custom implementation if:
/// - You have existing device IDs (from backend, device info, etc.)
/// - You need specific ID format requirements
/// - You want to sync identity across platforms
///
/// ### Example: Using Device Serial Number
///
/// ```dart
/// import 'package:device_info_plus/device_info_plus.dart';
///
/// class DeviceSerialIdentity implements DeviceIdentityProvider {
///   String? _cachedId;
///
///   @override
///   Future<String> getDeviceId() async {
///     if (_cachedId != null) return _cachedId!;
///
///     final deviceInfo = DeviceInfoPlugin();
///
///     if (Platform.isAndroid) {
///       final androidInfo = await deviceInfo.androidInfo;
///       _cachedId = 'android-${androidInfo.id}';
///     } else if (Platform.isIOS) {
///       final iosInfo = await deviceInfo.iosInfo;
///       _cachedId = 'ios-${iosInfo.identifierForVendor}';
///     } else {
///       // Fallback for other platforms
///       _cachedId = 'device-${DateTime.now().millisecondsSinceEpoch}';
///     }
///
///     return _cachedId!;
///   }
///
///   @override
///   Future<String?> getDeviceName() async {
///     final deviceInfo = DeviceInfoPlugin();
///
///     if (Platform.isAndroid) {
///       final androidInfo = await deviceInfo.androidInfo;
///       return '${androidInfo.brand} ${androidInfo.model}';
///     } else if (Platform.isIOS) {
///       final iosInfo = await deviceInfo.iosInfo;
///       return iosInfo.name;
///     }
///
///     return null;
///   }
/// }
/// ```
///
/// ### Example: User-Assigned IDs
///
/// ```dart
/// class UserAssignedIdentity implements DeviceIdentityProvider {
///   final SharedPreferences _prefs;
///
///   UserAssignedIdentity(this._prefs);
///
///   @override
///   Future<String> getDeviceId() async {
///     var deviceId = _prefs.getString('device_id');
///
///     if (deviceId == null) {
///       // Prompt user to enter device ID
///       deviceId = await _promptUserForDeviceId();
///       await _prefs.setString('device_id', deviceId);
///     }
///
///     return deviceId;
///   }
///
///   @override
///   Future<String?> getDeviceName() async {
///     return _prefs.getString('device_name');
///   }
///
///   Future<void> setDeviceName(String name) async {
///     await _prefs.setString('device_name', name);
///   }
/// }
/// ```
///
/// ## Thread Safety
///
/// Implementations should handle concurrent calls gracefully:
/// ```dart
/// class SafeIdentityProvider implements DeviceIdentityProvider {
///   Future<String>? _initFuture;
///   String? _deviceId;
///
///   @override
///   Future<String> getDeviceId() async {
///     if (_deviceId != null) return _deviceId!;
///
///     // Ensure only one init happens even with concurrent calls
///     _initFuture ??= _initialize();
///     await _initFuture;
///
///     return _deviceId!;
///   }
///
///   Future<void> _initialize() async {
///     // Generate or load device ID
///     _deviceId = await _loadOrGenerateId();
///   }
/// }
/// ```
abstract class DeviceIdentityProvider {
  /// Returns a stable unique identifier for this device.
  ///
  /// This method should:
  /// - Return the same ID across app restarts
  /// - Complete quickly (use caching if needed)
  /// - Never throw exceptions (provide fallback)
  ///
  /// **ID Format Recommendations:**
  /// - Use lowercase alphanumeric + hyphens
  /// - Keep length reasonable (8-64 characters)
  /// - Include a prefix for readability
  ///
  /// Good examples:
  /// - `"device-abc123def456"`
  /// - `"tablet-001"`
  /// - `"ios-E621E1F8-C36C-495A-93FC-0C247A3E6E5F"`
  ///
  /// Bad examples:
  /// - `"1"` (too short, high collision risk)
  /// - `"ThisIsMyLongDeviceIdentifierWithLotsOfWords"` (too long)
  /// - Random binary/hex dumps (not readable)
  ///
  /// **Caching:**
  /// ```dart
  /// String? _cachedId;
  ///
  /// @override
  /// Future<String> getDeviceId() async {
  ///   return _cachedId ??= await _loadFromStorage();
  /// }
  /// ```
  Future<String> getDeviceId();

  /// Returns an optional human-readable name for this device.
  ///
  /// This is used for:
  /// - Displaying in peer lists ("John's iPad", "Counter 1")
  /// - Debugging (logs, error reports)
  /// - UI personalization
  ///
  /// Can return `null` if not applicable or not available.
  ///
  /// Examples:
  /// - `"Admin Device"`
  /// - `"Check-in Counter 3"`
  /// - `"iPad Pro (John)"`
  /// - `"Samsung Galaxy S21"`
  ///
  /// **Note:** Unlike [getDeviceId], this can change over time
  /// (e.g., user renames device).
  Future<String?> getDeviceName() => Future.value(null);
}
