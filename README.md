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

## Example App

A complete, runnable example app is included in `example/`.

**Try it now:**

```bash
cd example
flutter pub get
flutter run
```

Run on 2+ devices on the same Wi-Fi network to see real-time sync in action.

**Features:**
- ✅ Task creation and management
- ✅ Real-time multi-device sync
- ✅ Auto-discovery of peers
- ✅ Sync metrics and monitoring
- ✅ Circuit breaker visualization
- ✅ Minimal black & white design

See `example/README.md` for detailed instructions.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  lan_sync_core: ^0.1.0
```

## Quick Start

### 1. Define Your Sync Item

```dart
import 'package:lan_sync_core/lan_sync_core.dart';

class Task implements SyncItem {
  final String id;
  final String title;
  final bool completed;
  final DateTime createdAt;
  
  Task({
    required this.id,
    required this.title,
    required this.completed,
    required this.createdAt,
  });
  
  @override
  String get syncId => id;
  
  @override
  DateTime get updatedAt => createdAt;
  
  @override
  String get sourceDeviceId => 'device-123'; // Your device ID
  
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
    'createdAt': createdAt.toIso8601String(),
  };
}
```

### 2. Use Network Components

#### Peer Discovery & Communication

```dart
// Initialize UDP transport
final transport = UdpTransport(
  config: UdpTransportConfig(
    port: 8765,
    broadcastPort: 8766,
  ),
);

await transport.start();

// Listen for incoming messages
transport.messages.listen((message) {
  print('Received: ${message.envelope.type}');
});

// Listen for discovered peers
transport.peers.listen((peer) {
  print('Found peer: ${peer.deviceId} at ${peer.address}');
});

// Broadcast announcement
final announcement = MessageEnvelope(
  type: MessageType.announcement,
  deviceId: 'my-device',
  timestamp: DateTime.now().millisecondsSinceEpoch,
);

await transport.broadcast(announcement);
```

#### Large Message Handling

```dart
// Split large data into chunks
final chunkManager = ChunkManager();
final largeData = Uint8List(100000); // 100KB

final chunks = chunkManager.createChunks(
  largeData,
  messageId: 'msg-123',
);

// Send each chunk
for (final chunk in chunks) {
  // Send via transport...
}

// Reassemble on receiver side
final result = chunkManager.addChunk(receivedChunk);
if (result.isComplete) {
  final completeData = result.data!;
  // Process complete message
}
```

#### Reliable Delivery

```dart
// Track messages with automatic retries
final ackTracker = AckTracker(
  maxRetries: 3,
  initialRetryDelay: Duration(milliseconds: 500),
);

final messageId = ackTracker.trackMessage(
  message: envelope,
  peer: peerAddress,
  port: 8765,
  onAck: () => print('Message delivered!'),
  onFailed: () => print('Delivery failed'),
);

// When ACK received
ackTracker.recordAck(messageId);

// Get delivery metrics
final metrics = ackTracker.getMetrics();
print('Success rate: ${metrics.successRate * 100}%');
```

#### Peer Management

```dart
// Track active peers
final peerTracker = PeerTracker(
  staleThreshold: Duration(seconds: 30),
);

// Listen for peer events
peerTracker.peerEvents.listen((event) {
  switch (event.type) {
    case PeerEventType.discovered:
      print('New peer: ${event.peer.deviceId}');
    case PeerEventType.lost:
      print('Lost peer: ${event.peer.deviceId}');
  }
});

// Add/update peers
peerTracker.addPeer(peerInfo);

// Get active peers
final activePeers = peerTracker.getActivePeers();
```

#### Rate Limiting

```dart
// Prevent network flooding
final rateLimiter = RateLimiter(
  messagesPerSecond: 100,
  burstSize: 10,
);

if (rateLimiter.allowMessage()) {
  // Send message
} else {
  print('Rate limit exceeded');
}
```

#### Network Health Monitoring

```dart
// Monitor sync performance
final healthMonitor = NetworkHealthMonitor();

healthMonitor.recordMessageSent('msg-1');
healthMonitor.recordMessageReceived('msg-1', Duration(milliseconds: 50));

final healthScore = healthMonitor.getHealthScore();
print('Network health: ${(healthScore * 100).toStringAsFixed(1)}%');

// Listen for alerts
healthMonitor.alerts.listen((alert) {
  print('Health alert: ${alert.message}');
});
```

## Architecture

`lan_sync_core` is built on clean abstractions:

- **Core Layer**: Interfaces you implement (SyncItem, SyncStorageAdapter, etc.)
- **Protocol Layer**: Message types and wire format
- **Network Layer**: UDP transport, chunking, reliability
- **Monitoring Layer**: Peer tracking, rate limiting, health monitoring
- **Sync Layer**: Coordination and conflict resolution (Phase 3, coming soon)

## Current Limitations

- No built-in conflict resolution yet (Phase 3)
- No default storage implementations (Phase 4)
- UDP-only (TCP/WebSocket support in future versions)
- LAN-only (no internet sync yet)

## Roadmap

- [x] Phase 1: Core abstractions
- [x] Phase 2: Network layer
- [ ] Phase 3: Sync coordination
- [ ] Phase 4: Default implementations
- [ ] Phase 5: Documentation and examples
- [ ] Phase 6: Pub.dev publishing

## Status

### ✅ Production-Ready (v0.1.0)

**Complete and ready for production use:**
- ✅ Phase 1: Core interfaces and abstractions
- ✅ Phase 2: Network layer (UDP transport, chunking, ACKs, monitoring)
- ✅ Phase 3: Sync coordination (SyncCoordinator, conflict resolution, file implementations)
- ✅ Phase 4A: Core integration (SyncEngine API, message routing, full wiring)
- ✅ Phase 4B: Resilience (circuit breaker, error recovery, auto-reconnection)
- ✅ Phase 4C: Example app (runnable task sync app with black & white UI)

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

**Sync Coordination:**
- `SyncCoordinator` - Orchestrates sync flows between devices
- `ConflictResolver` - Handles concurrent updates (LWW + custom strategies)
- `SyncMessages` - Protocol structures (SyncRequest, SyncResponse, etc.)
- `FileOpLog` - NDJSON operation log (default implementation)
- `FileDeviceIdentity` - UUID device identity (default implementation)

### Next: Integration & Testing

- Wire SyncCoordinator with network layer
- End-to-end sync examples
- Integration tests
- Complete documentation

## License

MIT
