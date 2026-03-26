# LAN Sync Example App

A minimal, black & white task sync app demonstrating `lan_sync_core` usage.

## Features

- ✅ Create and manage tasks
- ✅ Real-time sync across devices on the same LAN
- ✅ Auto-discovery of peers
- ✅ Circuit breaker for failing peers
- ✅ Sync metrics and monitoring
- ✅ Minimal, modern black & white design

## Running the App

### Prerequisites

- Flutter SDK (3.0.0+)
- 2+ devices/emulators on the same network

### Setup

1. **Install dependencies:**
   ```bash
   cd example
   flutter pub get
   ```

2. **Run on first device:**
   ```bash
   flutter run
   ```

3. **Run on second device:**
   ```bash
   flutter run -d <device-id>
   ```

   Find device IDs with:
   ```bash
   flutter devices
   ```

### Testing Sync

1. **Open app on both devices**
2. **Wait for peer discovery** (5-10 seconds)
3. **Add a task on Device A** → should appear on Device B within seconds
4. **Toggle/complete a task on Device B** → should sync to Device A
5. **Tap sync button** to manually sync with all peers
6. **Tap status button** to view:
   - Connected peers
   - Sync metrics
   - Recent events
   - Circuit breaker status

## UI Overview

### Tasks Screen

- **Add task:** Type + press Enter or tap +
- **Complete task:** Tap checkbox
- **Delete task:** Swipe left
- **Manual sync:** Tap sync icon (top-right)
- **View status:** Tap info icon (top-right)

### Sync Status Screen

Shows:
- Number of connected peers
- Per-peer sync metrics (success rate, failures)
- Circuit breaker status (green dot = OK, red dot = circuit open)
- Recent sync events
- Total sync statistics

## Design

**Theme:** Minimal black & white
- **Background:** White
- **Text:** Black / Gray
- **Accents:** None (pure B&W)
- **Typography:** System fonts, clean spacing
- **Components:** Minimal borders, no shadows

## Architecture

```
main.dart
  ↓
SyncEngine.create()
  ↓
TasksScreen (UI)
  ↓
TaskStorage (in-memory)
  ↓
SyncCoordinator (background sync)
```

**Storage:** In-memory (tasks cleared on restart)
- For production, use ObjectBox, Hive, SQLite, or Isar

**Serialization:** Simple JSON
- Tasks sync via JSON serialization

**Event Handling:** Debug prints
- Logs sync events to console

## Troubleshooting

### Peers not discovered

- Ensure both devices are on the same Wi-Fi network
- Check firewall settings (UDP port 8765 must be open)
- Wait 10-15 seconds for discovery
- Try manual sync button

### Sync not working

- Check sync status screen for errors
- Look for circuit breaker (red dot next to peer)
- Check console logs for detailed events
- Try restarting both apps

### Circuit breaker opened

- Appears as red dot in status screen
- Means 3+ consecutive sync failures with that peer
- Will auto-reset on successful sync
- Exponential backoff: 1min → 2min → 4min

## Console Logs

The app logs all sync events:

```
Devices changed: 1 connected
Item received: 1234-5678
Sync completed: 5 items
Circuit breaker opened: device-123
Peer reconnected: device-123
```

Filter logs:
```bash
flutter logs | grep "Sync\|Device\|Item"
```

## Code Structure

```
lib/
├── main.dart              # App entry + sync initialization
├── models/
│   └── task.dart          # Task model (extends SyncItem)
├── storage/
│   └── task_storage.dart  # In-memory storage adapter
├── serializer/
│   └── task_serializer.dart  # JSON serialization
├── screens/
│   ├── tasks_screen.dart     # Main task list UI
│   └── sync_status_screen.dart  # Sync monitoring UI
└── theme/
    └── app_theme.dart     # Black & white theme
```

## Next Steps

For production apps:

1. **Replace in-memory storage** with persistent DB:
   - ObjectBox (recommended for performance)
   - Hive (simple key-value)
   - SQLite (relational)
   - Isar (NoSQL)

2. **Add authentication:**
   - Device pairing
   - User accounts
   - Access control

3. **Add custom conflict resolution:**
   ```dart
   final resolver = CustomConflictResolver<Task>((local, remote) {
     // Your custom logic
     return local.priority > remote.priority ? local : remote;
   });
   ```

4. **Add persistent storage for sync state:**
   - Device identity
   - Operation logs
   - Sync cursors

5. **Add network health monitoring:**
   - Show connection quality
   - Retry failed syncs
   - Alert on sync issues

## License

Same as lan_sync_core package.
