# Changelog

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
