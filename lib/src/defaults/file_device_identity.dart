import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../core/device_identity_provider.dart';

/// File-based device identity provider.
///
/// Generates a stable UUID for the device and persists it to a file.
/// Once generated, the same device ID is used across all app restarts.
///
/// The device name is also stored (hostname on desktop, OS name on mobile).
///
/// File format (JSON):
/// ```json
/// {
///   "deviceId": "dev-a1b2c3d4-e5f6-7890-abcd-ef1234567890",
///   "deviceName": "MacBook-Pro",
///   "createdAt": "2026-03-26T07:15:00.000Z"
/// }
/// ```
///
/// Example:
/// ```dart
/// final identity = FileDeviceIdentity(
///   filePath: '/path/to/device_identity.json',
/// );
///
/// final deviceId = await identity.getDeviceId();
/// // First call: generates and saves
/// // Future calls: loads from file
///
/// final deviceName = await identity.getDeviceName();
/// // Returns saved device name
/// ```
class FileDeviceIdentity implements DeviceIdentityProvider {
  /// Path to the identity file
  final String filePath;

  /// Cached device ID (loaded on first call)
  String? _cachedDeviceId;

  /// Cached device name (loaded on first call)
  String? _cachedDeviceName;

  /// UUID generator
  static const _uuid = Uuid();

  FileDeviceIdentity({required this.filePath});

  @override
  Future<String> getDeviceId() async {
    // Return cached if already loaded
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    final file = File(filePath);

    // Load existing identity
    if (await file.exists()) {
      await _loadFromFile(file);
    } else {
      // Generate new identity
      await _generateAndSave(file);
    }

    return _cachedDeviceId!;
  }

  @override
  Future<String?> getDeviceName() async {
    // Ensure device ID is loaded (which also loads device name)
    await getDeviceId();
    return _cachedDeviceName;
  }

  /// Load identity from existing file
  Future<void> _loadFromFile(File file) async {
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      _cachedDeviceId = json['deviceId'] as String;
      _cachedDeviceName = json['deviceName'] as String?;
    } catch (e) {
      // File corrupted - regenerate
      await _generateAndSave(file);
    }
  }

  /// Generate new identity and save to file
  Future<void> _generateAndSave(File file) async {
    _cachedDeviceId = _generateDeviceId();
    _cachedDeviceName = await _generateDeviceName();

    final identity = {
      'deviceId': _cachedDeviceId,
      'deviceName': _cachedDeviceName,
      'createdAt': DateTime.now().toIso8601String(),
    };

    // Create parent directories if needed
    await file.parent.create(recursive: true);

    // Write to file
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(identity),
    );
  }

  /// Generate a unique device ID
  String _generateDeviceId() {
    return 'dev-${_uuid.v4()}';
  }

  /// Generate a human-readable device name
  Future<String> _generateDeviceName() async {
    try {
      // Try to get hostname (works on Linux/macOS)
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('hostname', []);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim();
        }
      }

      // Try to get computer name on Windows
      if (Platform.isWindows) {
        final result = await Process.run('hostname', []);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim();
        }
      }

      // Fallback to OS name
      return Platform.operatingSystem;
    } catch (e) {
      // Last resort fallback
      return 'Unknown Device';
    }
  }

  /// Reset device identity (generates new ID)
  ///
  /// Use with caution - this will create a new device identity
  /// and may cause sync issues with existing devices.
  Future<void> reset() async {
    _cachedDeviceId = null;
    _cachedDeviceName = null;

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }

    await getDeviceId(); // Regenerate
  }
}
