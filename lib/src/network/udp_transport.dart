import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'message_envelope.dart';
import 'message_type.dart';

/// Configuration for UDP transport
class UdpTransportConfig {
  /// UDP port for peer-to-peer communication
  final int port;

  /// Broadcast port for peer discovery
  final int broadcastPort;

  /// Enable IPv6 support
  final bool enableIPv6;

  /// Enable multicast for efficient group communication
  final bool enableMulticast;

  /// Multicast address (if enabled)
  final String multicastAddress;

  /// Maximum packet size before chunking is required
  final int maxPacketSize;

  /// Timeout for socket operations
  final Duration socketTimeout;

  /// Number of retry attempts for sending
  final int maxRetries;

  const UdpTransportConfig({
    this.port = 8765,
    this.broadcastPort = 8766,
    this.enableIPv6 = false,
    this.enableMulticast = true,
    this.multicastAddress = '224.0.0.251', // mDNS multicast group
    this.maxPacketSize = 65000, // Leave room for UDP header
    this.socketTimeout = const Duration(seconds = 5),
    this.maxRetries = 3,
  });
}

/// UDP transport layer for LAN synchronization
///
/// Handles:
/// - Socket lifecycle management
/// - Broadcast/unicast/multicast messaging
/// - Network interface detection
/// - Message routing
/// - Connection health
class UdpTransport {
  final UdpTransportConfig config;

  RawDatagramSocket? _unicastSocket;
  RawDatagramSocket? _broadcastSocket;
  RawDatagramSocket? _multicastSocket;

  final _messageController = StreamController<UdpMessage>.broadcast();
  final _peerController = StreamController<PeerInfo>.broadcast();

  bool _isRunning = false;
  List<NetworkInterface> _activeInterfaces = [];

  /// Stream of incoming messages
  Stream<UdpMessage> get messages => _messageController.stream;

  /// Stream of discovered peers
  Stream<PeerInfo> get peers => _peerController.stream;

  /// Whether transport is currently running
  bool get isRunning => _isRunning;

  /// List of active network interfaces
  List<NetworkInterface> get activeInterfaces =>
      List.unmodifiable(_activeInterfaces);

  UdpTransport({UdpTransportConfig? config})
    : config = config ?? const UdpTransportConfig();

  /// Start the UDP transport
  Future<void> start() async {
    if (_isRunning) {
      throw StateError('Transport is already running');
    }

    try {
      // Detect active network interfaces
      await _detectNetworkInterfaces();

      if (_activeInterfaces.isEmpty) {
        throw StateError('No active network interfaces found');
      }

      // Bind unicast socket for direct communication
      await _bindUnicastSocket();

      // Bind broadcast socket for peer discovery
      await _bindBroadcastSocket();

      // Bind multicast socket if enabled
      if (config.enableMulticast) {
        await _bindMulticastSocket();
      }

      _isRunning = true;

      print('[UdpTransport] Started on port ${config.port}');
      print(
        '[UdpTransport] Active interfaces: ${_activeInterfaces.map((i) => i.name).join(", ")}',
      );
    } catch (e) {
      await stop();
      rethrow;
    }
  }

  /// Stop the UDP transport
  Future<void> stop() async {
    _isRunning = false;

    _unicastSocket?.close();
    _broadcastSocket?.close();
    _multicastSocket?.close();

    _unicastSocket = null;
    _broadcastSocket = null;
    _multicastSocket = null;

    await _messageController.close();
    await _peerController.close();

    print('[UdpTransport] Stopped');
  }

  /// Send a message to a specific peer (unicast)
  Future<bool> sendTo(InternetAddress address, MessageEnvelope message) async {
    if (!_isRunning) {
      throw StateError('Transport is not running');
    }

    try {
      final bytes = _encodeMessage(message);

      // If message exceeds max packet size, caller must handle chunking
      if (bytes.length > config.maxPacketSize) {
        throw ArgumentError(
          'Message size (${bytes.length}) exceeds max packet size (${config.maxPacketSize}). '
          'Use ChunkManager for large payloads.',
        );
      }

      final sent = _unicastSocket!.send(bytes, address, config.port);
      return sent == bytes.length;
    } catch (e) {
      print('[UdpTransport] Error sending to $address: $e');
      return false;
    }
  }

  /// Broadcast a message to all peers on the network
  Future<bool> broadcast(MessageEnvelope message) async {
    if (!_isRunning) {
      throw StateError('Transport is not running');
    }

    try {
      final bytes = _encodeMessage(message);

      if (bytes.length > config.maxPacketSize) {
        throw ArgumentError('Message too large for broadcast');
      }

      // Send to broadcast address on each active interface
      var success = true;
      for (final interface in _activeInterfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            // Calculate broadcast address
            final broadcastAddr = _getBroadcastAddress(addr);
            final sent = _broadcastSocket!.send(
              bytes,
              broadcastAddr,
              config.broadcastPort,
            );
            success = success && (sent == bytes.length);
          }
        }
      }

      return success;
    } catch (e) {
      print('[UdpTransport] Error broadcasting: $e');
      return false;
    }
  }

  /// Multicast a message to the multicast group
  Future<bool> multicast(MessageEnvelope message) async {
    if (!_isRunning || !config.enableMulticast) {
      return false;
    }

    try {
      final bytes = _encodeMessage(message);
      final multicastAddr = InternetAddress(config.multicastAddress);

      final sent = _multicastSocket!.send(bytes, multicastAddr, config.port);
      return sent == bytes.length;
    } catch (e) {
      print('[UdpTransport] Error multicasting: $e');
      return false;
    }
  }

  /// Detect active network interfaces
  Future<void> _detectNetworkInterfaces() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.any,
    );

    // Filter to interfaces with valid addresses
    _activeInterfaces = interfaces.where((interface) {
      return interface.addresses.any(
        (addr) =>
            addr.type == InternetAddressType.IPv4 ||
            (config.enableIPv6 && addr.type == InternetAddressType.IPv6),
      );
    }).toList();
  }

  /// Bind unicast socket for direct peer-to-peer communication
  Future<void> _bindUnicastSocket() async {
    _unicastSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      config.port,
    );

    _unicastSocket!.broadcastEnabled = false;
    _unicastSocket!.listen(_handleUnicastPacket);
  }

  /// Bind broadcast socket for peer discovery
  Future<void> _bindBroadcastSocket() async {
    _broadcastSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      config.broadcastPort,
    );

    _broadcastSocket!.broadcastEnabled = true;
    _broadcastSocket!.listen(_handleBroadcastPacket);
  }

  /// Bind multicast socket for efficient group communication
  Future<void> _bindMulticastSocket() async {
    _multicastSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      config.port,
    );

    final multicastAddr = InternetAddress(config.multicastAddress);

    // Join multicast group on all active interfaces
    for (final interface in _activeInterfaces) {
      _multicastSocket!.joinMulticast(multicastAddr, interface);
    }

    _multicastSocket!.listen(_handleMulticastPacket);
  }

  /// Handle incoming unicast packet
  void _handleUnicastPacket(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _unicastSocket!.receive();
      if (datagram != null) {
        _processIncomingDatagram(datagram, isUnicast: true);
      }
    }
  }

  /// Handle incoming broadcast packet
  void _handleBroadcastPacket(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _broadcastSocket!.receive();
      if (datagram != null) {
        _processIncomingDatagram(datagram, isBroadcast: true);
      }
    }
  }

  /// Handle incoming multicast packet
  void _handleMulticastPacket(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _multicastSocket!.receive();
      if (datagram != null) {
        _processIncomingDatagram(datagram, isMulticast: true);
      }
    }
  }

  /// Process an incoming datagram
  void _processIncomingDatagram(
    Datagram datagram, {
    bool isUnicast = false,
    bool isBroadcast = false,
    bool isMulticast = false,
  }) {
    try {
      final message = _decodeMessage(datagram.data);

      final udpMessage = UdpMessage(
        envelope: message,
        sourceAddress: datagram.address,
        sourcePort: datagram.port,
        isUnicast: isUnicast,
        isBroadcast: isBroadcast,
        isMulticast: isMulticast,
        receivedAt: DateTime.now(),
      );

      _messageController.add(udpMessage);

      // If this is an announcement, emit peer info
      if (message.type == MessageType.announcement) {
        _peerController.add(
          PeerInfo(
            deviceId: message.senderId,
            address: datagram.address,
            port: datagram.port,
            lastSeen: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      print(
        '[UdpTransport] Error processing datagram from ${datagram.address}: $e',
      );
    }
  }

  /// Encode message to bytes
  Uint8List _encodeMessage(MessageEnvelope message) {
    final json = message.toJson();
    final jsonString = jsonEncode(json);
    return Uint8List.fromList(utf8.encode(jsonString));
  }

  /// Decode bytes to message
  MessageEnvelope _decodeMessage(Uint8List bytes) {
    final jsonString = utf8.decode(bytes);
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return MessageEnvelope.fromJson(json);
  }

  /// Calculate broadcast address for a given IP
  InternetAddress _getBroadcastAddress(InternetAddress address) {
    // For simplicity, use 255.255.255.255 (limited broadcast)
    // In production, calculate based on network mask
    return InternetAddress('255.255.255.255');
  }
}

/// Represents an incoming UDP message with metadata
class UdpMessage {
  final MessageEnvelope envelope;
  final InternetAddress sourceAddress;
  final int sourcePort;
  final bool isUnicast;
  final bool isBroadcast;
  final bool isMulticast;
  final DateTime receivedAt;

  const UdpMessage({
    required this.envelope,
    required this.sourceAddress,
    required this.sourcePort,
    this.isUnicast = false,
    this.isBroadcast = false,
    this.isMulticast = false,
    required this.receivedAt,
  });
}

/// Represents information about a discovered peer
class PeerInfo {
  final String deviceId;
  final InternetAddress address;
  final int port;
  final DateTime lastSeen;

  const PeerInfo({
    required this.deviceId,
    required this.address,
    required this.port,
    required this.receivedAt,
  });
}
