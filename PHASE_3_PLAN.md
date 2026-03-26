# Phase 3: Sync Coordination - Comprehensive Plan

**Goal:** Build the orchestration layer that coordinates actual data synchronization between peers using the network layer we built in Phase 2.

**Timeline:** 6-8 hours  
**Complexity:** High (this is the core sync logic)  
**Quality Bar:** Production-grade, handles all edge cases

---

## Architecture Overview

Phase 3 connects everything together:

```
┌─────────────────────────────────────────────────────────┐
│                      SyncEngine                         │
│  (User-facing API, lifecycle, configuration)            │
└───────────────────┬─────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
        ▼           ▼           ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ Storage  │ │  Sync    │ │ Network  │
│ Adapter  │ │Coordinator│ │ Layer    │
└──────────┘ └──────────┘ └──────────┘
     │            │             │
     │            │             │
     ▼            ▼             ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│  OpLog   │ │Conflict  │ │  UDP     │
│          │ │Resolution│ │Transport │
└──────────┘ └──────────┘ └──────────┘
```

---

## Component 1: SyncCoordinator

**Purpose:** State machine that orchestrates sync flows between peers

### Responsibilities

1. **Sync Flow Management**
   - Initiate full sync with discovered peers
   - Handle incoming sync requests
   - Coordinate incremental syncs
   - Track active sync sessions

2. **State Machine**
   ```
   IDLE → DISCOVERING → REQUESTING → RECEIVING → APPLYING → COMPLETE
     ↓                                                          ↓
     └──────────────────── IDLE ←───────────────────────────────┘
   ```

3. **Message Handling**
   - SYNC_REQUEST: "I need data"
   - SYNC_RESPONSE: "Here's my data"
   - ITEM_CREATED: "New item broadcast"
   - SYNC_COMPLETE: "Sync finished"

4. **Session Management**
   - Track which peers we're syncing with
   - Timeout stale sync sessions
   - Prevent duplicate syncs
   - Queue sync requests

### API Design

```dart
class SyncCoordinator<T extends SyncItem> {
  final SyncStorageAdapter<T> storage;
  final SyncSerializer<T> serializer;
  final UdpTransport transport;
  final OpLogAdapter opLog;
  final ConflictResolver<T> conflictResolver;
  
  // Initiate full sync with a peer
  Future<SyncResult> syncWithPeer(PeerInfo peer);
  
  // Handle incoming sync request from peer
  Future<void> handleSyncRequest(String peerId, SyncRequest request);
  
  // Broadcast new item to all peers
  Future<void> broadcastItem(T item);
  
  // Get sync status
  SyncStatus getStatus();
  
  // Stream of sync events
  Stream<SyncEvent> get events;
}
```

### Key Features

- **Incremental sync**: Only send operations since last sync
- **Range-based sync**: Use OpLog cursors to track what's been synced
- **Concurrent sync**: Handle multiple peers syncing simultaneously
- **Idempotency**: Handle duplicate messages gracefully
- **Backpressure**: Don't overwhelm network with too many sync sessions

### Edge Cases to Handle

1. Peer disconnects mid-sync → Resume or restart on reconnect
2. Same item updated on multiple devices → Conflict resolution
3. Network partition → Eventual consistency when reconnected
4. Clock skew between devices → Use Lamport timestamps
5. Large dataset → Sync in batches, not all at once
6. Corrupted data → Checksum verification, reject bad data

---

## Component 2: Conflict Resolution

**Purpose:** Handle concurrent updates to the same item on different devices

### Strategy: Last-Write-Wins (LWW) with Vector Clocks

**Why LWW?**
- Simple to implement
- Easy to reason about
- Works for 90% of use cases
- Can be extended to custom strategies later

### Implementation

```dart
abstract class ConflictResolver<T extends SyncItem> {
  /// Resolve conflict between local and remote versions
  /// Returns the winning item
  T resolve(T local, T remote);
}

class LastWriteWinsResolver<T extends SyncItem> implements ConflictResolver<T> {
  @override
  T resolve(T local, T remote) {
    // Compare timestamps
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      return remote; // Remote wins
    } else if (local.updatedAt.isAfter(remote.updatedAt)) {
      return local; // Local wins
    } else {
      // Same timestamp - use device ID as tiebreaker
      return local.sourceDeviceId.compareTo(remote.sourceDeviceId) > 0
          ? local
          : remote;
    }
  }
}

// Future: Custom resolver
class CustomConflictResolver<T extends SyncItem> implements ConflictResolver<T> {
  final T Function(T local, T remote) customLogic;
  
  @override
  T resolve(T local, T remote) => customLogic(local, remote);
}
```

### Conflict Detection

```dart
class ConflictDetector<T extends SyncItem> {
  /// Check if two items conflict
  bool hasConflict(T local, T remote) {
    // Same item (by syncId) but different content
    return local.syncId == remote.syncId &&
           !_areEqual(local, remote) &&
           !local.updatedAt.isAtSameMomentAs(remote.updatedAt);
  }
  
  bool _areEqual(T a, T b) {
    // Deep equality check via JSON
    return const DeepCollectionEquality()
        .equals(a.toJson(), b.toJson());
  }
}
```

### Conflict Logging

```dart
class ConflictLog {
  final String itemId;
  final DateTime detectedAt;
  final Map<String, dynamic> localVersion;
  final Map<String, dynamic> remoteVersion;
  final String resolution; // 'local' or 'remote'
  final String reason;
}
```

**Emit conflict events so users can audit/debug conflicts.**

---

## Component 3: FileOpLog (Default Implementation)

**Purpose:** NDJSON file-based operation log for tracking sync operations

### File Format

```
{opId: 1, ts: 1234567890, entity: "task", opType: "create", payload: {...}, deviceId: "dev-1"}
{opId: 2, ts: 1234567891, entity: "task", opType: "update", payload: {...}, deviceId: "dev-1"}
{opId: 3, ts: 1234567892, entity: "task", opType: "delete", payload: {...}, deviceId: "dev-2"}
```

Each line is a JSON object, newline-delimited.

### Implementation

```dart
class FileOpLog implements OpLogAdapter {
  final String filePath;
  final DeviceIdentityProvider deviceIdentity;
  
  int _lastOpId = 0;
  RandomAccessFile? _file;
  final _lock = Lock(); // Prevent concurrent writes
  
  @override
  Future<OpLogEntry> appendLocalOp({
    required String entity,
    required String opType,
    required Map<String, dynamic> payload,
  }) async {
    return await _lock.synchronized(() async {
      final deviceId = await deviceIdentity.getDeviceId();
      final entry = OpLogEntry(
        opId: (++_lastOpId).toString(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        entity: entity,
        opType: opType,
        payload: payload,
        sourceDeviceId: deviceId,
        logIndex: _lastOpId,
      );
      
      // Append to file
      await _appendToFile(entry);
      
      return entry;
    });
  }
  
  @override
  Future<List<OpLogEntry>> getOpsSince(int sinceCursor) async {
    // Read file, parse NDJSON, filter by cursor
    final lines = await File(filePath).readAsLines();
    
    return lines
        .skip(sinceCursor)
        .map((line) => OpLogEntry.fromJson(jsonDecode(line)))
        .toList();
  }
  
  @override
  int get lastOpId => _lastOpId;
  
  Future<void> _appendToFile(OpLogEntry entry) async {
    _file ??= await File(filePath).open(mode: FileMode.append);
    await _file!.writeString('${jsonEncode(entry.toJson())}\n');
    await _file!.flush();
  }
  
  // Compaction: remove old entries (optional optimization)
  Future<void> compact({int keepLast = 1000}) async {
    final allOps = await getOpsSince(0);
    
    if (allOps.length <= keepLast) return;
    
    final toKeep = allOps.skip(allOps.length - keepLast);
    
    // Rewrite file
    await File(filePath).writeAsString(
      toKeep.map((e) => '${jsonEncode(e.toJson())}\n').join(),
    );
  }
}
```

### Features

- Append-only (never modify existing entries)
- Thread-safe (synchronized writes)
- Fast reads (memory-mapped if large)
- Optional compaction (keep last N entries)
- Crash-safe (each line is atomic)

---

## Component 4: FileDeviceIdentity (Default Implementation)

**Purpose:** Generate and persist stable device ID

### Implementation

```dart
class FileDeviceIdentity implements DeviceIdentityProvider {
  final String filePath;
  String? _cachedDeviceId;
  String? _cachedDeviceName;
  
  @override
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    
    final file = File(filePath);
    
    if (await file.exists()) {
      final content = await file.readAsString();
      final json = jsonDecode(content);
      _cachedDeviceId = json['deviceId'];
      _cachedDeviceName = json['deviceName'];
    } else {
      // Generate new ID
      _cachedDeviceId = _generateDeviceId();
      _cachedDeviceName = await _generateDeviceName();
      
      await file.writeAsString(jsonEncode({
        'deviceId': _cachedDeviceId,
        'deviceName': _cachedDeviceName,
        'createdAt': DateTime.now().toIso8601String(),
      }));
    }
    
    return _cachedDeviceId!;
  }
  
  @override
  Future<String?> getDeviceName() async {
    await getDeviceId(); // Ensure loaded
    return _cachedDeviceName;
  }
  
  String _generateDeviceId() {
    // UUID v4
    return 'dev-${Uuid().v4()}';
  }
  
  Future<String> _generateDeviceName() async {
    // Platform-specific: get hostname or device model
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('hostname', []);
        return result.stdout.toString().trim();
      } else if (Platform.isAndroid || Platform.isIOS) {
        // Use device_info_plus package
        return Platform.operatingSystem;
      }
    } catch (e) {
      // Fallback
    }
    return 'Unknown Device';
  }
}
```

### File Format

```json
{
  "deviceId": "dev-a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "deviceName": "MacBook-Pro",
  "createdAt": "2026-03-26T07:15:00.000Z"
}
```

---

## Component 5: SyncEngine (Main Orchestrator)

**Purpose:** User-facing API that wires everything together

### API Design

```dart
class SyncEngine<T extends SyncItem> {
  final SyncConfig config;
  final SyncStorageAdapter<T> storage;
  final SyncSerializer<T> serializer;
  final SyncEventHandler eventHandler;
  final DeviceIdentityProvider? deviceIdentity;
  final OpLogAdapter? opLog;
  
  // Internal components (created automatically)
  late final UdpTransport _transport;
  late final ChunkManager _chunkManager;
  late final AckTracker _ackTracker;
  late final PeerTracker _peerTracker;
  late final RateLimiter _rateLimiter;
  late final NetworkHealthMonitor _healthMonitor;
  late final SyncCoordinator<T> _coordinator;
  
  SyncEngine({
    required this.config,
    required this.storage,
    required this.serializer,
    required this.eventHandler,
    this.deviceIdentity,
    this.opLog,
  });
  
  /// Start the sync engine
  Future<void> start() async {
    // Initialize device identity
    _deviceId = await (deviceIdentity ?? _createDefaultIdentity()).getDeviceId();
    
    // Initialize network layer
    _transport = UdpTransport(config: config.transportConfig);
    await _transport.start();
    
    _chunkManager = ChunkManager();
    _ackTracker = AckTracker();
    _peerTracker = PeerTracker();
    _rateLimiter = RateLimiter(
      messagesPerSecond: config.maxMessagesPerSecond,
      burstSize: config.burstSize,
    );
    _healthMonitor = NetworkHealthMonitor();
    
    // Initialize sync coordinator
    _coordinator = SyncCoordinator(
      storage: storage,
      serializer: serializer,
      transport: _transport,
      opLog: opLog ?? _createDefaultOpLog(),
      conflictResolver: config.conflictResolver ?? LastWriteWinsResolver<T>(),
    );
    
    // Wire up event handlers
    _setupEventHandlers();
    
    // Start background tasks
    _startHeartbeat();
    _startPeerDiscovery();
  }
  
  /// Stop the sync engine
  Future<void> stop() async {
    await _transport.stop();
    _ackTracker.dispose();
    _peerTracker.dispose();
    _rateLimiter.dispose();
    _healthMonitor.dispose();
  }
  
  /// Add an item to sync
  Future<void> addItem(T item) async {
    await storage.upsertItem(item);
    await _coordinator.broadcastItem(item);
  }
  
  /// Manually trigger sync with all peers
  Future<void> syncNow() async {
    final peers = _peerTracker.getActivePeers();
    for (final peer in peers) {
      await _coordinator.syncWithPeer(peer);
    }
  }
  
  /// Get current sync status
  SyncStatus get status => _coordinator.getStatus();
  
  /// Get active peers
  List<PeerInfo> get activePeers => _peerTracker.getActivePeers();
  
  /// Get network health score
  double get healthScore => _healthMonitor.getHealthScore();
}
```

### Configuration

```dart
class SyncConfig {
  final UdpTransportConfig transportConfig;
  final int maxMessagesPerSecond;
  final int burstSize;
  final Duration heartbeatInterval;
  final Duration syncInterval;
  final ConflictResolver? conflictResolver;
  final String? deviceIdentityPath;
  final String? opLogPath;
  
  const SyncConfig({
    this.transportConfig = const UdpTransportConfig(),
    this.maxMessagesPerSecond = 100,
    this.burstSize = 10,
    this.heartbeatInterval = const Duration(seconds: 10),
    this.syncInterval = const Duration(seconds: 30),
    this.conflictResolver,
    this.deviceIdentityPath,
    this.opLogPath,
  });
}
```

### Lifecycle

```
User calls start()
  ↓
Initialize device identity
  ↓
Start UDP transport
  ↓
Initialize network components
  ↓
Initialize sync coordinator
  ↓
Wire up event handlers
  ↓
Start heartbeat (every 10s)
  ↓
Start peer discovery
  ↓
Listen for peers and messages
  ↓
Auto-sync when peers discovered
  ↓
User calls stop()
  ↓
Clean shutdown
```

---

## Sync Flow: Full Sync Between Two Devices

### Scenario: Device A and Device B discover each other

```
Device A                                    Device B
   |                                           |
   | ──── ANNOUNCEMENT (broadcast) ────────▶  |
   |                                           |
   | ◀──── ANNOUNCEMENT (broadcast) ────────  |
   |                                           |
   | (both discover each other)                |
   |                                           |
   | ──── SYNC_REQUEST ─────────────────────▶ |
   |      { sinceCursor: 0 }                   |
   |                                           |
   |                                    (B reads OpLog)
   |                                    (B prepares items)
   |                                           |
   | ◀──── SYNC_RESPONSE ────────────────────  |
   |      { items: [...], cursor: 42 }         |
   |                                           |
   | (A receives items)                        |
   | (A detects conflicts)                     |
   | (A resolves conflicts)                    |
   | (A saves to storage)                      |
   | (A updates OpLog)                         |
   |                                           |
   | ──── SYNC_COMPLETE ─────────────────────▶ |
   |      { cursor: 42 }                       |
   |                                           |
   | ──── ACK ───────────────────────────────▶ |
   |                                           |
```

### Incremental Sync

```
Device A                                    Device B
   |                                           |
   | ──── SYNC_REQUEST ─────────────────────▶ |
   |      { sinceCursor: 42 }                  |
   |                                           |
   |                                    (B reads OpLog since 42)
   |                                    (B finds 3 new ops)
   |                                           |
   | ◀──── SYNC_RESPONSE ────────────────────  |
   |      { items: [3 items], cursor: 45 }     |
   |                                           |
```

**Key: Incremental sync only sends operations since last cursor.**

---

## Message Protocol Extensions

New message types for Phase 3:

```dart
enum MessageType {
  // Existing (Phase 1 & 2)
  announcement,
  heartbeat,
  ack,
  
  // New (Phase 3)
  syncRequest,      // "I need data since cursor X"
  syncResponse,     // "Here's data, cursor now Y"
  syncComplete,     // "Sync finished successfully"
  itemCreated,      // "New item broadcast"
  itemUpdated,      // "Item changed broadcast"
  itemDeleted,      // "Item removed broadcast"
}
```

### Message Payloads

**SYNC_REQUEST:**
```json
{
  "type": "syncRequest",
  "deviceId": "dev-123",
  "timestamp": 1711422900000,
  "payload": {
    "sinceCursor": 42,
    "entity": "task"
  }
}
```

**SYNC_RESPONSE:**
```json
{
  "type": "syncResponse",
  "deviceId": "dev-456",
  "timestamp": 1711422901000,
  "payload": {
    "items": [...],
    "cursor": 45,
    "totalItems": 3
  }
}
```

**ITEM_CREATED:**
```json
{
  "type": "itemCreated",
  "deviceId": "dev-123",
  "timestamp": 1711422902000,
  "payload": {
    "item": {...},
    "opLogEntry": {...}
  }
}
```

---

## Testing Strategy

### Unit Tests (per component)

1. **SyncCoordinator**
   - Test full sync flow
   - Test incremental sync
   - Test concurrent syncs
   - Test error handling

2. **Conflict Resolution**
   - Test LWW with various timestamps
   - Test tie-breaking with device IDs
   - Test custom resolvers

3. **FileOpLog**
   - Test append operations
   - Test read since cursor
   - Test compaction
   - Test concurrent writes

4. **FileDeviceIdentity**
   - Test ID generation
   - Test persistence
   - Test loading

5. **SyncEngine**
   - Test full lifecycle
   - Test event wiring
   - Test error recovery

### Integration Tests

1. **Two-device sync** (simulated)
   - Start two engines
   - Add items on each
   - Verify both sync

2. **Three-device mesh** (simulated)
   - A, B, C all sync with each other
   - Verify eventual consistency

3. **Network partition**
   - Disconnect mid-sync
   - Verify recovery on reconnect

4. **Concurrent updates**
   - Same item updated on two devices
   - Verify conflict resolution

5. **Large dataset**
   - 1000+ items
   - Verify chunking works
   - Verify performance

---

## Success Criteria

Phase 3 is complete when:

✅ All 5 components implemented  
✅ Full sync flow works end-to-end  
✅ Incremental sync works  
✅ Conflict resolution works  
✅ Default implementations work  
✅ Integration tests pass  
✅ Documentation complete  
✅ Example app demonstrates sync  
✅ Zero compilation errors  
✅ Clean analysis  

---

## Task Breakdown (Estimated Times)

| Task | Component | Time |
|------|-----------|------|
| 1 | SyncCoordinator core | 90 min |
| 2 | Message protocol extensions | 30 min |
| 3 | Conflict resolution | 45 min |
| 4 | FileOpLog | 60 min |
| 5 | FileDeviceIdentity | 30 min |
| 6 | SyncEngine orchestrator | 90 min |
| 7 | Integration & testing | 90 min |
| 8 | Documentation & examples | 45 min |

**Total:** 7.5 hours

---

## Risks & Mitigation

### Risk 1: Complexity
**Issue:** Sync coordination is complex, easy to get wrong  
**Mitigation:** Start simple (full sync only), add incremental later  

### Risk 2: Edge Cases
**Issue:** Many edge cases (disconnects, conflicts, corruption)  
**Mitigation:** Comprehensive tests, defensive programming  

### Risk 3: Performance
**Issue:** Large datasets might be slow  
**Mitigation:** Batching, chunking, pagination  

### Risk 4: Data Loss
**Issue:** Bugs could cause data loss  
**Mitigation:** OpLog is append-only, never delete without backup  

---

## Dependencies

**New packages needed:**
- `uuid` - For device ID generation
- `synchronized` - For file locking
- `collection` - For deep equality checks
- `path_provider` - For default file paths (Flutter)

**Add to pubspec.yaml:**
```yaml
dependencies:
  crypto: ^3.0.5
  uuid: ^4.0.0
  synchronized: ^3.1.0
  collection: ^1.18.0
  path_provider: ^2.1.0  # Flutter only
```

---

## Next Steps

Once this plan is approved:

1. ✅ Review plan with user (you approve)
2. ⏳ Task 1: Implement SyncCoordinator
3. ⏳ Task 2: Extend MessageProtocol
4. ⏳ Task 3: Implement conflict resolution
5. ⏳ Task 4: Implement FileOpLog
6. ⏳ Task 5: Implement FileDeviceIdentity
7. ⏳ Task 6: Implement SyncEngine
8. ⏳ Task 7: Integration tests
9. ⏳ Task 8: Documentation

**Ready to build when you approve this plan.** 🚀

---

**End of Phase 3 Plan**
