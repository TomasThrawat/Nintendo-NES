import 'dart:async';
import 'dart:io';

import '../core/controller/nes_controller.dart';
import 'remote_protocol.dart';

/// WiFiPad-style IP-only UDP receiver for fixed-size NES input frames.
/// Keep this port on a trusted local network because packets are unauthenticated.
class LocalControllerServer {
  LocalControllerServer({
    required this.onButtonsChanged,
    required this.onStatusChanged,
    this.onInputCountChanged,
    this.port = nesWifiPort,
  });

  final int port;
  final void Function(Set<NesButton>) onButtonsChanged;
  final void Function(String) onStatusChanged;
  final void Function(int)? onInputCountChanged;

  RawDatagramSocket? _socket;
  Timer? _watchdog;
  InternetAddress? _peerAddress;
  int? _peerPort;
  int _lastSequence = -1;
  int _inputsReceived = 0;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  List<String> addresses = const <String>[];

  static const Duration _failsafeTimeout = Duration(milliseconds: 750);

  bool get isListening => _socket != null;
  bool get isConnected => _peerAddress != null;
  int get boundPort => _socket?.port ?? port;
  int get inputsReceived => _inputsReceived;

  Future<void> start() async {
    if (_socket != null) {
      return;
    }
    _inputsReceived = 0;
    _lastSequence = -1;
    onInputCountChanged?.call(0);
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      _socket = socket;
      socket.readEventsEnabled = true;
      socket.writeEventsEnabled = false;
      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            _receivePending();
          }
        },
        onError: (Object _) {
          onStatusChanged('Local Wi-Fi receiver error');
        },
        onDone: () {
          if (_socket != null) {
            _dropPeer(status: 'Receiver stopped');
          }
        },
        cancelOnError: true,
      );
      addresses = await _localIpv4Addresses();
      _watchdog?.cancel();
      _watchdog = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _checkTimeout(),
      );
      onStatusChanged('Waiting for NES controller');
    } on SocketException {
      _socket?.close();
      _socket = null;
      onStatusChanged('Could not open the local Wi-Fi UDP port.');
      rethrow;
    }
  }

  Future<void> stop() async {
    _watchdog?.cancel();
    _watchdog = null;
    _dropPeer(status: 'Receiver stopped');
    _socket?.close();
    _socket = null;
    addresses = const <String>[];
    _inputsReceived = 0;
    _lastSequence = -1;
    onInputCountChanged?.call(0);
    onButtonsChanged(const <NesButton>{});
    onStatusChanged('Stopped');
  }

  void _receivePending() {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) {
        return;
      }
      _handleDatagram(datagram);
    }
  }

  void _handleDatagram(Datagram datagram) {
    if (!isNesInputPacket(datagram.data) ||
        !isValidNesDatagram(datagram.data)) {
      return;
    }

    final sequence = readNesSequence(datagram.data);
    final mask = readNesButtonMask(datagram.data);
    final samePeer = _peerAddress?.address == datagram.address.address &&
        _peerPort == datagram.port;

    if (_peerAddress != null && !samePeer) {
      if (DateTime.now().difference(_lastFrame) <= _failsafeTimeout) {
        return;
      }
      _dropPeer(status: 'Controller disconnected');
    }

    if (_peerAddress == null) {
      _peerAddress = datagram.address;
      _peerPort = datagram.port;
      _lastSequence = -1;
      onButtonsChanged(const <NesButton>{});
      onStatusChanged('Controller connected');
    }

    if (!isNewerNesSequence(sequence, _lastSequence)) {
      return;
    }

    _lastSequence = sequence;
    _lastFrame = DateTime.now();
    _inputsReceived++;
    onInputCountChanged?.call(_inputsReceived);
    onButtonsChanged(NesController.buttonsFromMask(mask));

    // An ACK lets the controller verify receiver reachability.
    _socket?.send(
      encodeNesAckPacket(sequence: sequence),
      datagram.address,
      datagram.port,
    );
  }

  void _checkTimeout() {
    if (_peerAddress != null &&
        DateTime.now().difference(_lastFrame) > _failsafeTimeout) {
      _dropPeer(status: 'Controller disconnected');
    }
  }

  void _dropPeer({required String status}) {
    if (_peerAddress == null) {
      return;
    }
    _peerAddress = null;
    _peerPort = null;
    _lastSequence = -1;
    onButtonsChanged(const <NesButton>{});
    onStatusChanged(status);
  }

  /// Refresh the displayed IPv4 list after changing the Wi-Fi network.
  Future<List<String>> refreshAddresses() async {
    addresses = await _localIpv4Addresses();
    return addresses;
  }

  Future<List<String>> _localIpv4Addresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final preferred = <String>[];
      final fallback = <String>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (address.isLoopback ||
              ip.startsWith('169.254.') ||
              ip == '0.0.0.0') {
            continue;
          }
          fallback.add(ip);
          final name = interface.name.toLowerCase();
          if (name.contains('wlan') || name.contains('wifi')) {
            preferred.add(ip);
          }
        }
      }
      return (preferred.isNotEmpty ? preferred : fallback).toSet().toList()
        ..sort();
    } on SocketException {
      return const <String>[];
    }
  }
}
