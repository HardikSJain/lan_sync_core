# lan_sync_core

A Flutter/Dart package for offline-first multi-device synchronization on local area networks (LAN).

## Overview

`lan_sync_core` enables peer-to-peer data synchronization between devices on the same local network, without requiring a central server or internet connection. Perfect for event check-ins, field operations, classroom attendance, and other multi-device scenarios where devices need to stay in sync locally.

## Features

- **Automatic peer discovery** via UDP broadcast
- **Real-time synchronization** across devices on the same LAN
- **Offline-first** architecture
- **Chunked message handling** for large payloads
- **Automatic retry and acknowledgment** mechanisms
- **Network health monitoring**
- **Pluggable storage adapters**

## Use Cases

- Event check-in and registration systems
- Classroom/training attendance tracking
- Field data collection and surveys
- Warehouse and inventory management
- Temporary offline coordination
- Local collaborative experiences

## Getting Started

> **Note:** This package is currently in early development.

Documentation and examples will be added as the package evolves.

## Status

### Phase 2: Network Layer ✅ (Complete)

Current progress:
- ✅ Phase 1: Core interfaces and abstractions
- ✅ Phase 2: Network layer (UDP transport, chunking, ACKs, monitoring)
- ⏳ Phase 3: Sync coordination (in progress)
- ⏳ Phase 4: Default implementations
- ⏳ Phase 5: Documentation and examples

### Implemented Components (v0.1.0-dev)

**Core Abstractions:**
- `SyncItem` - Interface for synchronized objects
- `SyncStorageAdapter` - Database integration interface
- `SyncSerializer` - JSON serialization interface
- `SyncEventHandler` - Event callback interface
- `DeviceIdentityProvider` - Device identification interface
- `OpLogEntry` - Operation log structure

**Network Layer:**
- `UdpTransport` - UDP socket management, peer discovery (broadcast/unicast/multicast)
- `ChunkManager` - Large payload splitting and reassembly (MD5 checksums)
- `AckTracker` - Reliable delivery with retries and exponential backoff
- `MessageEnvelope` - Wire protocol message wrapper
- `MessageProtocol` - Message type definitions

**Monitoring:**
- `PeerTracker` - Active peer management with heartbeat monitoring
- `RateLimiter` - Token bucket rate limiting
- `NetworkHealthMonitor` - Health scoring and performance tracking

### Next: Phase 3 - Sync Coordination

- Sync state machine and coordination
- Conflict resolution
- Default implementations (FileOpLog, FileDeviceIdentity)
- Full end-to-end sync flow

## License

MIT
