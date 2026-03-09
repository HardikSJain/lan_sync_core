# P2P Expo → lan_sync_core: Architecture Analysis

**Date:** 2026-03-09  
**Analyst:** Jarvis  
**Source:** `p2p_expo_project/fitpage-p2p-expo-27ce9dfbb1e6/`

---

## Executive Summary

The P2P Expo app contains a sophisticated **offline-first LAN sync engine** that can be extracted into a reusable package. The current implementation is heavily coupled to:
- **ObjectBox** (specific database)
- **CheckInEntry** model (domain-specific)
- **Flutter** dependencies (path_provider, etc.)

**Extraction Strategy:** Abstract away app-specific components behind clean interfaces, preserving the core networking, sync coordination, and monitoring logic.

---

## Component Analysis

### ✅ Clean Components (Move as-is or minimal changes)

#### 1. **connected_device_tracker.dart**
- **Purpose:** Tracks active peers with presence/staleness detection
- **Dependencies:** `dart:io` only
- **Coupling:** None
- **Action:** Rename to `PeerTracker`, move to package as-is
- **LOC:** ~100

#### 2. **rate_limiter.dart**
- **Purpose:** Token bucket rate limiter
- **Dependencies:** Pure Dart
- **Coupling:** None
- **Action:** Move to package as-is
- **LOC:** ~50

#### 3. **network_health_monitor.dart**
- **Purpose:** Tracks sync metrics and health status
- **Dependencies:** `flutter/foundation` (debugPrint only)
- **Coupling:** Minimal
- **Action:** Replace `debugPrint` with logger interface, move to package
- **LOC:** ~100

---

### 🔀 Abstraction Needed

#### 4. **device_identity_store.dart**
- **Purpose:** Generates and persists stable device ID + operation sequence
- **Dependencies:** `path_provider`, `flutter/foundation`
- **Coupling:** File system, Flutter
- **Action:** 
  - Extract interface: `DeviceIdentityProvider`
  - Keep file-based implementation as **default** in package
  - Make it pluggable
- **LOC:** ~150

#### 5. **op_log_store.dart**
- **Purpose:** Append-only operation log (CRDT-style)
- **Dependencies:** `path_provider`, `flutter/foundation`, `DeviceIdentityStore`
- **Coupling:** File system, Flutter, app-specific assumptions
- **Action:**
  - Extract interface: `OpLogAdapter`
  - Keep NDJSON file implementation as **default** in package
  - Abstract `OpLogEntry` to generic structure
- **LOC:** ~400

#### 6. **snapshot_manager.dart**
- **Purpose:** Creates compressed snapshots of full dataset
- **Dependencies:** `crypto`, `path_provider`, `ObjectBoxService`, `OpLogStore`
- **Coupling:** **HEAVY** - ObjectBox, CheckInEntry
- **Action:**
  - Extract interface: `SnapshotProvider`
  - Defer HTTP snapshot serving to v0.2.0 (not needed for UDP-only)
  - User implements snapshot creation from their storage
- **LOC:** ~200

---

### 🏗️ Core Orchestrator (Major Refactor Needed)

#### 7. **check_in_sync_service.dart**
- **Purpose:** Main sync engine - orchestrates everything
- **Size:** **2000+ lines** (!)
- **Responsibilities:**
  - UDP socket management
  - Peer discovery (broadcast/unicast)
  - Message types (ANNOUNCEMENT, CHECK_IN_CREATED, SYNC_REQUEST, etc.)
  - Chunking/reassembly
  - ACK/retry mechanism
  - Checksum verification
  - Connectivity monitoring
  - HTTP sync coordination (optional)
  
- **Dependencies:**
  - All other services
  - ObjectBox
  - CheckInEntry
  - connectivity_plus
  
- **Coupling:** **MAXIMUM**
  
- **Action:**
  - **Split** into multiple focused classes:
    1. `SyncEngine` - main orchestrator
    2. `UdpTransport` - socket + messaging
    3. `MessageProtocol` - message types + serialization
    4. `ChunkManager` - chunking/reassembly
    5. `AckTracker` - reliability layer
    6. `SyncCoordinator` - sync flow state machine
  
  - **Abstract storage** via `SyncStorageAdapter<T>`
  - **Abstract serialization** via `SyncSerializer<T>`
  - **Abstract events** via `SyncEventHandler`
  
- **Complexity:** HIGH

---

### ❌ App-Specific (Stay in App)

#### 8. **objectbox_service.dart**
- **Purpose:** ObjectBox database facade
- **Action:** User implements `SyncStorageAdapter` for their DB
- **LOC:** ~400+

#### 9. **foreground_service_helper.dart**
- **Purpose:** Android foreground service
- **Action:** User handles platform-specific services
- **LOC:** Unknown

#### 10. **api_service.dart**
- **Purpose:** Backend API client
- **Action:** Not relevant to LAN sync
- **LOC:** Unknown

---

## Dependency Graph

```
check_in_sync_service (CORE)
├── connected_device_tracker ✅
├── device_identity_store 🔀
├── op_log_store 🔀
├── snapshot_manager 🔀 (v0.2.0)
├── edge_http_server ⏭️ (defer to v0.2.0)
├── range_sync_client ⏭️ (defer to v0.2.0)
├── rate_limiter ✅
├── network_health_monitor ✅
├── objectbox_service ❌ (user implements adapter)
├── foreground_service_helper ❌ (user handles)
└── connectivity_plus 📦 (add as package dependency)

Models:
├── check_in_entry ❌ (user defines SyncItem impl)
├── user ❌
└── login_model ❌
```

**Legend:**
- ✅ Move as-is
- 🔀 Abstract + provide default
- ⏭️ Defer to later version
- ❌ User responsibility
- 📦 Package dependency

---

## Key Abstractions

### 1. **SyncItem** (Interface)
Replaces `CheckInEntry` with generic sync-able entity.

```dart
abstract class SyncItem {
  String get syncId;
  DateTime get createdAt;
  DateTime get updatedAt;
  String get sourceDeviceId;
  Map<String, dynamic> toJson();
}
```

### 2. **SyncStorageAdapter<T>** (Interface)
Replaces direct ObjectBox calls.

```dart
abstract class SyncStorageAdapter<T extends SyncItem> {
  Future<List<T>> getAllItems();
  Future<T?> getItemBySyncId(String syncId);
  Future<bool> upsertItem(T item);
  Future<Map<String, int>> batchUpsertItems(List<T> items);
  Future<int> getItemCount();
}
```

### 3. **SyncSerializer<T>** (Interface)
Handles item ↔ JSON conversion.

```dart
abstract class SyncSerializer<T extends SyncItem> {
  Map<String, dynamic> itemToJson(T item);
  T itemFromJson(Map<String, dynamic> json);
  List<Map<String, dynamic>> encodeItemList(List<T> items);
  List<T> decodeItemList(List<dynamic> jsonList);
}
```

### 4. **SyncEventHandler** (Interface)
Replaces callbacks.

```dart
abstract class SyncEventHandler {
  void onDevicesChanged(Set<String> deviceIds);
  void onConnectionStateChanged(bool isConnected);
  void onItemReceived(SyncItem item);
  void onSyncCompleted(int itemsReceived);
  void onSyncFailed(String reason);
  void onSyncEvent(String event, String message);
}
```

### 5. **DeviceIdentityProvider** (Interface)
```dart
abstract class DeviceIdentityProvider {
  Future<String> getDeviceId();
  Future<String?> getDeviceName();
}
```

### 6. **OpLogAdapter** (Interface)
```dart
abstract class OpLogAdapter {
  Future<OpLogEntry> appendLocalOp({...});
  Future<OpLogEntry?> recordExternalOp(OpLogEntry entry);
  Future<List<OpLogEntry>> getOpsSince(int sinceCursor);
  int get lastOpId;
}
```

---

## Message Protocol (UDP)

Current message types that need to be preserved:

### Core Messages (v0.1.0)
1. **ANNOUNCEMENT** - Device discovery
2. **HEARTBEAT** - Keep-alive
3. **SYNC_REQUEST** - Request full sync
4. **SYNC_RESPONSE** - Full dataset
5. **SYNC_RESPONSE_CHUNK** - Chunked dataset
6. **SYNC_RESEND_REQUEST** - Request missing chunks
7. **CHECK_IN_CREATED** - New item broadcast (→ **ITEM_CREATED**)
8. **ACK** - Acknowledgment
9. **CHECKSUM_VERIFY** - Integrity check

### Deferred (v0.2.0)
- HTTP-based bulk sync messages
- Metadata-based sync
- Specific-ID requests

---

## Package Structure (v0.1.0)

```
lan_sync_core/
├── lib/
│   ├── lan_sync_core.dart
│   ├── src/
│   │   ├── core/
│   │   │   ├── sync_engine.dart              ← Main API
│   │   │   ├── sync_item.dart
│   │   │   ├── sync_storage_adapter.dart
│   │   │   ├── sync_serializer.dart
│   │   │   ├── sync_event_handler.dart
│   │   │   └── device_identity_provider.dart
│   │   ├── network/
│   │   │   ├── udp_transport.dart            ← Socket mgmt
│   │   │   ├── message_protocol.dart         ← Message types
│   │   │   ├── chunk_manager.dart            ← Chunking
│   │   │   └── ack_tracker.dart              ← Reliability
│   │   ├── sync/
│   │   │   ├── sync_coordinator.dart         ← Sync flows
│   │   │   ├── op_log.dart                   ← OpLog interface
│   │   │   └── checksum.dart                 ← Verification
│   │   ├── monitoring/
│   │   │   ├── network_health.dart
│   │   │   ├── rate_limiter.dart
│   │   │   └── peer_tracker.dart
│   │   ├── utils/
│   │   │   ├── connectivity_monitor.dart
│   │   │   └── message_dedup.dart
│   │   └── defaults/
│   │       ├── file_device_identity.dart     ← Default impl
│   │       └── file_op_log.dart              ← Default impl
│   └── presets/
│       └── default_config.dart
```

---

## Migration Checklist

### Phase 1: Interfaces & Core (Week 1)
- [ ] Define all abstract interfaces
- [ ] Create `SyncItem`, `SyncStorageAdapter`, etc.
- [ ] Write comprehensive documentation
- [ ] Add interface tests

### Phase 2: Network Layer (Week 1-2)
- [ ] Extract UDP socket logic → `UdpTransport`
- [ ] Extract message types → `MessageProtocol`
- [ ] Extract chunking → `ChunkManager`
- [ ] Extract ACK tracking → `AckTracker`
- [ ] Unit tests for each

### Phase 3: Sync Coordination (Week 2)
- [ ] Extract sync state machine → `SyncCoordinator`
- [ ] Extract checksum logic
- [ ] Extract peer discovery flow
- [ ] Integration tests

### Phase 4: Monitoring (Week 2)
- [ ] Move `PeerTracker`
- [ ] Move `RateLimiter`
- [ ] Move `NetworkHealthMonitor`
- [ ] Tests

### Phase 5: Defaults (Week 3)
- [ ] Implement `FileDeviceIdentity`
- [ ] Implement `FileOpLog`
- [ ] Test defaults work standalone

### Phase 6: Main Orchestrator (Week 3)
- [ ] Create `SyncEngine` that wires everything together
- [ ] Clean public API
- [ ] Full integration test

### Phase 7: Example App (Week 3-4)
- [ ] Build minimal example
- [ ] Implement all required interfaces
- [ ] End-to-end test
- [ ] Tutorial documentation

### Phase 8: App Migration (Week 4)
- [ ] Add `lan_sync_core` to expo app
- [ ] Implement adapters for ObjectBox
- [ ] Replace `CheckInSyncService` with package
- [ ] Verify all features still work
- [ ] Remove old code

---

## v0.1.0 Scope (UDP-Only)

### ✅ Include
- Peer discovery (UDP broadcast)
- Full sync (UDP unicast/broadcast)
- Chunking/reassembly
- ACK/retry
- Checksum verification
- Rate limiting
- Network health monitoring
- Basic op-log support
- Connectivity monitoring

### ❌ Exclude (v0.2.0+)
- HTTP bulk sync
- Edge server
- Snapshot serving
- Advanced conflict resolution
- Encryption/authentication

---

## Risk Assessment

### High Risk
1. **Sync engine complexity** - 2000 lines to split carefully
2. **Message protocol compatibility** - Must preserve wire format
3. **State management** - Current service has complex state

### Medium Risk
1. **Chunking edge cases** - Large datasets, timeouts
2. **OpLog abstraction** - CRDT semantics must be preserved
3. **Testing coverage** - Need comprehensive tests

### Low Risk
1. **Peer tracking** - Clean, isolated
2. **Rate limiting** - Simple token bucket
3. **Health monitoring** - Stateless metrics

---

## Success Criteria

### v0.1.0 Release
- [ ] Package compiles with zero errors
- [ ] All interfaces documented with examples
- [ ] Example app works end-to-end
- [ ] Expo app migrated successfully
- [ ] No regressions in sync behavior
- [ ] 80%+ test coverage
- [ ] Pub.dev ready (score 130+)

---

## Next Steps

1. ✅ **Architecture analysis complete**
2. 🔄 **Get approval from Hardik**
3. ⏭️ Start Phase 1: Interface design
4. ⏭️ Create detailed API proposal
5. ⏭️ Begin extraction

---

**Status:** Analysis Complete, Awaiting Go-Ahead  
**Estimated Timeline:** 3-4 weeks to v0.1.0
