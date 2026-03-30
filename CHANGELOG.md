# Changelog

## 0.1.0 (2026-03-26)

### 🎉 Production Release

Complete, production-ready package for LAN-based peer-to-peer synchronization.

#### Example App

Added complete, runnable example app:
- Minimal black & white task sync app
- Real-time multi-device synchronization
- Sync status monitoring
- Circuit breaker visualization
- Clean, modern UI
- In-memory storage (swap for your DB)
- Comprehensive README with setup instructions

Location: `example/`

Run:
```bash
cd example
flutter pub get
flutter run
```

#### Complete Feature Set

✅ **Core Sync Engine**
- Simple initialization API
- Lifecycle management
- Auto-discovery & heartbeat
- Incremental & full sync
- Event streaming

✅ **Network Layer**
- UDP transport
- Chunking (1MB max)
- ACK tracking
- Rate limiting (100/sec)
- Health monitoring

✅ **Sync Coordination**
- Conflict resolution (LWW + custom)
- Operation log (NDJSON)
- Cursor-based incremental sync
- Multi-peer concurrent sync
- Message routing

✅ **Resilience**
- Circuit breaker (exponential backoff)
- Auto-reconnection
- Failure tracking & metrics
- Self-healing
- Graceful degradation

✅ **Quality**
- Zero compilation errors
- Zero warnings
- Zero analysis issues
- Comprehensive documentation
- Production-grade code

#### Package Status

- **Version:** 0.1.0 (production-ready)
- **Components:** 20+
- **Lines of Code:** ~6,000+
- **Test Status:** Example app functional
- **Documentation:** Complete

#### Usage

```dart
// 1. Create engine
final engine = await SyncEngine.create<Task>(
  storage: taskStorage,
  serializer: taskSerializer,
  eventHandler: myEventHandler,
);

// 2. Start sync
await engine.start();

// 3. Use it
await engine.syncWithAll();
await engine.broadcastChange(task);
```

See `example/` for complete working app.

### Breaking Changes

None (initial release)

---

## 0.1.0-dev.5 (2026-03-26)

### Phase 4B: Resilience & Error Recovery - Complete ✅

Production-grade error recovery, circuit breaker, and auto-reconnection.

#### Circuit Breaker Pattern

Prevents hammering failing peers with exponential backoff:
- Opens after 3 consecutive failures
- Exponential backoff: 1min → 2min → 4min → 8min → ... (max 30min)
- Auto-resets when peer recovers
- Reduces failure count on reconnection

#### Failure Tracking & Metrics

Detailed per-peer metrics:
- Total sync attempts
- Total successful syncs
- Consecutive failures
- Success rate (%)
- Last success timestamp
- Last failure timestamp
- Circuit breaker status

API:
```dart
// Get metrics for peer
final metrics = engine.getMetricsForPeer(peerId);
print(metrics.successRate); // 0.0 - 1.0
print(metrics.consecutiveFailures);
print(metrics.isCircuitOpen);

// Get all metrics
final allMetrics = engine.getAllMetrics();

// Reset metrics
engine.resetMetricsForPeer(peerId);
```

#### Auto-Reconnection

Automatic sync on peer discovery/reconnection:
- New peer discovered → auto-sync after 500ms
- Peer reconnected (after failures) → reduce failure count & auto-sync
- Circuit breaker aware (won't sync if circuit open)
- Graceful handling of transient failures

#### Enhanced Events

New event types:
- `peerDiscovered` - New peer found on network
- `peerReconnected` - Peer recovered after failures  
- `peerLost` - Peer went offline
- `syncSkipped` - Sync skipped (circuit breaker open)
- `circuitBreakerOpened` - Circuit opened after 3 failures
- `circuitBreakerReset` - Circuit reset (peer recovered)

#### Resilience Features

- ✅ Circuit breaker with exponential backoff
- ✅ Detailed failure tracking
- ✅ Success rate metrics
- ✅ Auto-reconnection on peer recovery
- ✅ Graceful degradation
- ✅ Self-healing (failure count reduction on reconnection)

#### Quality

- Zero compilation errors ✅
- Zero warnings ✅
- Zero infos ✅
- Production-grade resilience ✅

### Breaking Changes

None (development release)

---

## 0.1.0-dev.4 (2026-03-26)

### Phase 4A: Core Integration - Complete ✅

Production-ready, plug-and-play sync engine with full integration.

#### SyncEngine (High-Level API)

- **Simple initialization**: One factory method wires all components
- **Lifecycle management**: start/stop/dispose with proper cleanup
- **Automatic sync operations**:
  - syncWithAll() - sync with all active peers
  - syncWithPeer(id) - sync with specific peer
  - broadcastChange(item) - broadcast local changes
- **Event streaming**: Unified event stream for UI reactivity
- **Auto-heartbeat**: Periodic peer discovery broadcasts
- **Auto-sync**: Optional periodic sync with all peers
- **Graceful cleanup**: Stale session removal

#### Integration Complete

All components now wired together:
- DeviceIdentity → SyncCoordinator ✅
- PeerTracker → SyncCoordinator ✅
- MessageRouter → UdpTransport + SyncCoordinator ✅
- CursorStorage → SyncCoordinator ✅
- OpLog → SyncCoordinator ✅

#### Usage

```dart
// Create engine
final engine = await SyncEngine.create<Task>(
  storage: taskStorage,
  serializer: taskSerializer,
  eventHandler: myEventHandler,
);

// Start sync
await engine.start();

// Sync with all peers
await engine.syncWithAll();

// Broadcast change
await engine.broadcastChange(task);

// Listen to events
engine.events.listen((event) {
  print('Sync event: $event');
});

// Cleanup
await engine.dispose();
```

#### Quality

- Zero compilation errors ✅
- Zero warnings ✅
- Zero infos ✅
- Production-ready ✅
- Scalable ✅
- Highly reusable ✅

### Breaking Changes

None (development release)

---

## 0.1.0-dev.3 (2026-03-26)

### Phase 3: Sync Coordination - Core Implementation

Implemented core synchronization orchestration layer.

#### Sync Coordination

- **SyncCoordinator**: State machine for sync flows
  - Full sync and incremental sync
  - Concurrent session management
  - Incoming/outgoing sync request/response handling
  - Conflict resolution integration
  - Item broadcast to peers
  - Event emission for monitoring

- **Conflict Resolution**:
  - ConflictResolver abstract base
  - LastWriteWinsResolver (timestamp + device ID tiebreaker)
  - CustomConflictResolver (user-defined logic)
  - ConflictLog for debugging

- **Sync Messages**:
  - SyncRequest (cursor-based)
  - SyncResponse (operations payload)
  - ItemUpsertedMessage (broadcast changes)
  - SyncCompleteMessage (completion notification)

#### Default Implementations

- **FileDeviceIdentity**: UUID-based device ID
  - Persistent file storage
  - Platform-specific device names
  - Stable across restarts

- **FileOpLog**: NDJSON operation log
  - Append-only writes
  - Thread-safe (synchronized)
  - Cursor-based reads
  - Deduplication
  - Optional compaction

#### Dependencies Added

- uuid ^4.0.0
- synchronized ^3.1.0
- collection ^1.18.0

#### Quality

- Zero compilation errors
- Clean analysis
- Comprehensive dartdoc
- Production-ready error handling

### Breaking Changes

None (development release)

---

## 0.1.0-dev.2 (2026-03-26)

### Phase 2: Network Layer - Complete

Implemented complete UDP-based networking layer with reliability features.

#### Network Components

- **UdpTransport**: Production-grade UDP socket management
  - Broadcast peer discovery
  - Unicast and multicast messaging
  - Network interface detection
  - IPv4/IPv6 support
  - Configurable ports and timeouts

- **ChunkManager**: Large payload handling
  - Automatic chunking of messages exceeding 60KB
  - MD5 checksum verification per chunk
  - Intelligent reassembly with missing piece detection
  - Stale session cleanup (60s timeout)
  - Duplicate chunk handling

- **AckTracker**: Reliable delivery
  - Track sent messages awaiting acknowledgment
  - Automatic retries with exponential backoff (500ms, 1s, 2s)
  - Max 3 retry attempts
  - Delivery success/failure callbacks
  - Comprehensive metrics (success rate, avg latency)

#### Monitoring Components

- **PeerTracker**: Active peer management
  - Track discovered peers with metadata
  - Heartbeat monitoring (30s staleness threshold)
  - Automatic stale peer cleanup (every 10s)
  - Event stream for peer lifecycle (discovered, updated, lost)

- **RateLimiter**: Network flood prevention
  - Token bucket algorithm
  - Configurable rate (default: 100 msgs/sec)
  - Burst allowance (default: 10 tokens)
  - Automatic token refill
  - Real-time rate calculation

- **NetworkHealthMonitor**: Performance tracking
  - Message sent/received counters
  - Error categorization and tracking
  - Latency measurements
  - Health score calculation (0.0-1.0)
  - Alert system for degradation

#### Quality

- Zero compilation errors
- Clean dart analysis (no warnings)
- Comprehensive dartdoc comments
- Production-grade error handling
- Following Dart style guide

### Breaking Changes

None (initial development release)

---

## 0.1.0-dev.1 (2026-03-09)

### Phase 1: Core Interfaces

Initial release with core abstractions.

#### Features

- `SyncItem` interface for domain objects
- `SyncStorageAdapter<T>` for database integration
- `SyncSerializer<T>` for JSON conversion
- `SyncEventHandler` for event callbacks
- `DeviceIdentityProvider` for device identification
- `OpLogEntry` operation log structure
- `MessageEnvelope` wire protocol
- `MessageType` enum for message categorization

#### Documentation

- Architecture analysis
- Comprehensive interface documentation
- Examples for all interfaces

### Breaking Changes

None (initial release)
