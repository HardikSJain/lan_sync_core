# lan_sync_core Execution Plan

**Goal:** Build a production-grade, plug-and-play LAN synchronization package for Flutter/Dart

**Timeline:** Complete Phase 2 (Network Layer) today  
**Quality Standard:** Clean code, best practices, scalable, user-friendly

---

## Phase 2: Network Layer (Current Focus)

### Task 1: Fix UdpTransport Compilation Errors ⚠️ CRITICAL
**Current State:** 9 compilation errors  
**What's Wrong:**
- Duration constructor syntax errors
- Missing/incorrect field names (receivedAt vs lastSeen)
- MessageEnvelope.senderId doesn't exist (should be deviceId)

**Fix:**
1. Line 42: Change `Duration(seconds = 5)` to `Duration(seconds: 5)`
2. Line 331-335: Fix PeerInfo constructor - use `lastSeen` consistently
3. Line 332: Change `senderId` to `deviceId`
4. Line 396-400: Fix PeerInfo field initialization

**Estimated Time:** 15 minutes  
**Output:** Zero compilation errors

---

### Task 2: Implement Chunk Manager
**Purpose:** Handle large payloads that exceed UDP packet size (64KB)

**Features:**
- Split messages into chunks (with sequence numbers)
- Reassemble chunks back into complete messages
- Handle missing chunks (request retransmission)
- Timeout for incomplete reassembly
- Deduplication

**Architecture:**
```dart
class ChunkManager {
  // Outgoing: split message into chunks
  List<MessageChunk> createChunks(Uint8List data, {int maxChunkSize = 60000});
  
  // Incoming: reassemble chunks
  ReassemblyResult addChunk(MessageChunk chunk);
  
  // Cleanup: remove stale reassembly sessions
  void cleanupStale(Duration timeout);
}

class MessageChunk {
  final String messageId;      // Unique ID for this message
  final int sequenceNumber;     // 0, 1, 2, ...
  final int totalChunks;        // How many chunks total
  final Uint8List data;         // Chunk payload
  final String checksum;        // Verify integrity
}

class ReassemblyResult {
  final bool isComplete;        // All chunks received?
  final Uint8List? data;        // Complete message (if done)
  final Set<int> missingChunks; // Which chunks still needed
}
```

**Best Practices:**
- Use CRC32 or MD5 for chunk checksums
- Store reassembly state in memory (Map<messageId, ReassemblySession>)
- Auto-cleanup sessions older than 60 seconds
- Log chunk receive/send events for debugging

**Estimated Time:** 45 minutes  
**Output:** `lib/src/network/chunk_manager.dart`

---

### Task 3: Implement ACK Tracker
**Purpose:** Reliable message delivery with acknowledgments and retries

**Features:**
- Track sent messages waiting for ACK
- Automatic retries with exponential backoff
- ACK receipt processing
- Timeout detection
- Metrics (success rate, avg latency)

**Architecture:**
```dart
class AckTracker {
  // Send message and track it
  String sendWithAck(MessageEnvelope message, InternetAddress peer);
  
  // Record ACK received
  void recordAck(String messageId);
  
  // Check for timeouts and trigger retries
  List<RetryInfo> checkTimeouts();
  
  // Get metrics
  AckMetrics getMetrics();
}

class PendingMessage {
  final String messageId;
  final MessageEnvelope message;
  final InternetAddress peer;
  final DateTime sentAt;
  final int retryCount;
  final Duration nextRetry; // Exponential backoff
}

class AckMetrics {
  final int totalSent;
  final int totalAcked;
  final int totalRetried;
  final int totalFailed;
  final double successRate;
  final Duration averageLatency;
}
```

**Best Practices:**
- Max 3 retries before giving up
- Exponential backoff: 500ms, 1s, 2s
- Store pending messages in Map<messageId, PendingMessage>
- Emit events for delivery success/failure
- Clean up ACKed/failed messages after 5 minutes

**Estimated Time:** 45 minutes  
**Output:** `lib/src/network/ack_tracker.dart`

---

### Task 4: Implement Peer Tracker
**Purpose:** Manage discovered peers and their health status

**Features:**
- Track active peers
- Heartbeat monitoring
- Stale peer detection
- Peer capabilities/metadata

**Architecture:**
```dart
class PeerTracker {
  // Add/update peer
  void addPeer(PeerInfo peer);
  
  // Mark peer as seen (heartbeat)
  void markSeen(String deviceId);
  
  // Get active peers
  List<PeerInfo> getActivePeers({Duration staleThreshold = const Duration(seconds: 30)});
  
  // Remove stale peers
  List<String> removeStale();
  
  // Stream of peer changes
  Stream<PeerEvent> get peerEvents;
}

class PeerInfo {
  final String deviceId;
  final InternetAddress address;
  final int port;
  final DateTime lastSeen;
  final Map<String, dynamic>? metadata; // Optional capabilities
}

enum PeerEventType { discovered, lost, updated }

class PeerEvent {
  final PeerEventType type;
  final PeerInfo peer;
}
```

**Best Practices:**
- Consider peer stale after 30s without heartbeat
- Emit events when peers join/leave
- Store in Map<deviceId, PeerInfo>
- Periodic cleanup task (every 10s)

**Estimated Time:** 30 minutes  
**Output:** `lib/src/monitoring/peer_tracker.dart`

---

### Task 5: Implement Rate Limiter
**Purpose:** Prevent flooding the network with messages

**Features:**
- Token bucket algorithm
- Configurable rate (messages/second)
- Burst allowance
- Per-peer rate limiting (optional)

**Architecture:**
```dart
class RateLimiter {
  RateLimiter({required this.messagesPerSecond, required this.burstSize});
  
  // Check if message can be sent
  bool allowMessage();
  
  // Force consume a token (for tracking)
  void consumeToken();
  
  // Get current rate metrics
  RateLimitMetrics getMetrics();
}

class RateLimitMetrics {
  final int tokensAvailable;
  final int tokensConsumed;
  final int messagesBlocked;
  final double currentRate;
}
```

**Best Practices:**
- Default: 100 messages/second, burst of 10
- Refill tokens every 10ms
- Use a Timer for token refill
- Log blocked messages for debugging

**Estimated Time:** 30 minutes  
**Output:** `lib/src/monitoring/rate_limiter.dart`

---

### Task 6: Implement Network Health Monitor
**Purpose:** Track sync performance and detect issues

**Features:**
- Messages sent/received counters
- Error tracking
- Latency measurements
- Health score calculation

**Architecture:**
```dart
class NetworkHealthMonitor {
  // Record message sent
  void recordMessageSent(String messageId);
  
  // Record message received
  void recordMessageReceived(String messageId, Duration latency);
  
  // Record error
  void recordError(NetworkError error);
  
  // Get health metrics
  HealthMetrics getMetrics();
  
  // Get current health score (0.0 - 1.0)
  double getHealthScore();
}

class HealthMetrics {
  final int messagesSent;
  final int messagesReceived;
  final int errors;
  final Duration averageLatency;
  final double packetLossRate;
}

enum NetworkError { sendFailed, receiveFailed, timeout, checksumMismatch }
```

**Best Practices:**
- Calculate health score: (received / sent) * (1 - error_rate)
- Reset counters every hour to avoid overflow
- Expose metrics as stream for live monitoring
- Log errors with context

**Estimated Time:** 30 minutes  
**Output:** `lib/src/monitoring/network_health_monitor.dart`

---

### Task 7: Integration & Testing
**Purpose:** Wire everything together and verify it works

**Steps:**
1. Create `SyncEngine` orchestrator (Phase 3 preview)
2. Write example app that uses all components
3. Integration test: 2 devices sync data
4. Performance test: stress with 1000 messages
5. Error recovery test: disconnect/reconnect

**Estimated Time:** 60 minutes  
**Output:** 
- `lib/src/sync_engine.dart` (basic orchestrator)
- `example/basic_sync.dart`
- Tests pass

---

### Task 8: Documentation & Polish
**Purpose:** Make package ready for users

**Steps:**
1. Update README with quick start guide
2. Add dartdoc comments to all public APIs
3. Create API reference
4. Add usage examples
5. Update CHANGELOG

**Estimated Time:** 30 minutes  
**Output:** Complete documentation

---

## Quality Checklist

Before marking any task complete:

- [ ] `dart analyze` → 0 errors
- [ ] `dart format` → all files formatted
- [ ] All public APIs have dartdoc comments
- [ ] Edge cases handled
- [ ] Errors logged with context
- [ ] Code follows Dart style guide
- [ ] Git commit with clear message
- [ ] Pushed to GitHub

---

## Time Estimate

| Task | Time | Cumulative |
|------|------|------------|
| 1. Fix UdpTransport | 15 min | 15 min |
| 2. ChunkManager | 45 min | 60 min |
| 3. AckTracker | 45 min | 105 min |
| 4. PeerTracker | 30 min | 135 min |
| 5. RateLimiter | 30 min | 165 min |
| 6. HealthMonitor | 30 min | 195 min |
| 7. Integration | 60 min | 255 min |
| 8. Documentation | 30 min | 285 min |

**Total: ~5 hours**

---

## Success Criteria

Phase 2 is complete when:

✅ All code compiles with 0 errors  
✅ All components implemented and tested  
✅ Example app demonstrates full sync flow  
✅ Documentation is complete  
✅ Ready for pub.dev publishing (structure-wise)  

---

## Next: Phase 3 (Sync Coordination)

After Phase 2:
- SyncCoordinator (state machine)
- Conflict resolution (CRDT-based)
- Default implementations (FileOpLog, FileDeviceIdentity)
- Full sync flow orchestration

But that's for later. **Let's nail Phase 2 first.**

---

**Ready to execute. Starting with Task 1: Fix UdpTransport errors.**
