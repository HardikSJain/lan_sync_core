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

🚧 **Work in Progress**

Current progress:
- ✅ Architecture analysis completed
- ✅ Core interfaces defined
- ✅ Protocol/message model started
- ⏳ UDP transport layer next

## Current Scope (v0.1.0)

Focus is on a **UDP-only LAN sync package**:
- peer discovery
- full sync
- chunking/reassembly
- ACK/retry
- checksum verification

HTTP bulk sync / edge server will come later after the core UDP path is stable.

## License

MIT
