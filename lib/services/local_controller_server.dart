import 'dart:async';
import 'dart:io';

import '../core/controller/gamepad_state.dart';
import 'gamepad_protocol.dart';
import 'system_gamepad_bridge.dart';

/// Receives Wi-Fi controller frames and forwards button changes to Android's system gamepad.
class LocalControllerServer {
  LocalControllerServer({
    required this.onButtonsChanged,
    required this.onStatusChanged,
    this.onInputCountChanged,
    this.port = gamepadWifiPort,
    this.systemGamepadEnabled = true,
  });

  final int port;
  final void Function(Set<GamepadButton>) onButtonsChanged;
  final void Function(String) onStatusChanged;
  final void Function(int)? onInputCountChanged;
  final bool systemGamepadEnabled;
  RawDatagramSocket? _socket;
  Timer? _watchdog;
  InternetAddress? _peerAddress;
  int? _peerPort;
  int _lastSequence = -1;
  int _lastMask = 0;
  int _inputsReceived = 0;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  List<String> addresses = const <String>[];
  static const Duration _timeout = Duration(milliseconds: 750);

  bool get isListening => _socket != null;
  bool get isConnected => _peerAddress != null;
  int get boundPort => _socket?.port ?? port;
  int get inputsReceived => _inputsReceived;

  Future<void> start() async {
    if (_socket != null) return;
    _inputsReceived = 0;
    _lastSequence = -1;
    _lastMask = 0;
    onInputCountChanged?.call(0);
    var nativeStarted = false;
    try {
      if (systemGamepadEnabled) {
        await SystemGamepadBridge.start();
        nativeStarted = true;
      }
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, port, reuseAddress: true,
      );
      _socket = socket;
      socket.readEventsEnabled = true;
      socket.writeEventsEnabled = false;
      socket.listen(
        (event) {
          if (event == RawSocketEvent.read) _receivePending();
        },
        onError: (Object error) => onStatusChanged('Local Wi-Fi receiver error: $error'),
        onDone: () {
          if (_socket != null) _dropPeer('Receiver stopped');
        },
        cancelOnError: true,
      );
      addresses = await _localIpv4Addresses();
      _watchdog?.cancel();
      _watchdog = Timer.periodic(const Duration(milliseconds: 250), (_) => _checkTimeout());
      onStatusChanged(systemGamepadEnabled
          ? 'Virtual gamepad registered; waiting for controller'
          : 'Waiting for controller');
    } on Object catch (error) {
      _socket?.close();
      _socket = null;
      if (nativeStarted) {
        try { await SystemGamepadBridge.stop(); } on Object { }
      }
      onStatusChanged(error is SocketException
          ? 'Could not open the local Wi-Fi UDP port.'
          : error.toString());
      rethrow;
    }
  }

  Future<void> stop() async {
    _watchdog?.cancel();
    _watchdog = null;
    _dropPeer('Receiver stopped');
    _socket?.close();
    _socket = null;
    addresses = const <String>[];
    _inputsReceived = 0;
    _lastSequence = -1;
    _lastMask = 0;
    onInputCountChanged?.call(0);
    onButtonsChanged(const <GamepadButton>{});
    if (systemGamepadEnabled) {
      try { await SystemGamepadBridge.setButtons(const <GamepadButton>{}); } on Object { }
      await SystemGamepadBridge.stop();
    }
    onStatusChanged('Stopped');
  }

  void _receivePending() {
    final socket = _socket;
    if (socket == null) return;
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) return;
      _handleDatagram(datagram);
    }
  }

  void _handleDatagram(Datagram datagram) {
    if (!isGamepadInputPacket(datagram.data) || !isValidGamepadPacket(datagram.data)) return;
    final sequence = readGamepadSequence(datagram.data);
    final mask = readGamepadMask(datagram.data);
    final samePeer = _peerAddress?.address == datagram.address.address &&
        _peerPort == datagram.port;

    if (_peerAddress != null && !samePeer) {
      if (DateTime.now().difference(_lastFrame) <= _timeout) return;
      _dropPeer('Controller disconnected');
    }
    if (_peerAddress == null) {
      _peerAddress = datagram.address;
      _peerPort = datagram.port;
      _lastSequence = -1;
      _lastMask = -1;
      onStatusChanged('Controller connected');
    }
    if (!isNewerGamepadSequence(sequence, _lastSequence)) return;
    _lastSequence = sequence;
    _lastFrame = DateTime.now();
    _inputsReceived++;
    onInputCountChanged?.call(_inputsReceived);
    if (mask != _lastMask) {
      _lastMask = mask;
      onButtonsChanged(GamepadState.buttonsFromMask(mask));
    }
    _socket?.send(
      encodeGamepadAckPacket(sequence: sequence),
      datagram.address,
      datagram.port,
    );
  }

  void _checkTimeout() {
    if (_peerAddress != null && DateTime.now().difference(_lastFrame) > _timeout) {
      _dropPeer('Controller disconnected');
    }
  }

  void _dropPeer(String status) {
    if (_peerAddress == null) return;
    _peerAddress = null;
    _peerPort = null;
    _lastSequence = -1;
    _lastMask = 0;
    onButtonsChanged(const <GamepadButton>{});
    onStatusChanged(status);
  }

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
          if (address.isLoopback || ip.startsWith('169.254.') || ip == '0.0.0.0') continue;
          fallback.add(ip);
          final name = interface.name.toLowerCase();
          if (name.contains('wlan') || name.contains('wifi')) preferred.add(ip);
        }
      }
      return (preferred.isNotEmpty ? preferred : fallback).toSet().toList()..sort();
    } on SocketException {
      return const <String>[];
    }
  }
}
