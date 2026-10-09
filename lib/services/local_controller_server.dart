import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/controller/nes_controller.dart';
import 'remote_protocol.dart';

/// Single-controller local TCP host. No input history or network logs are stored.
class LocalControllerServer {
  LocalControllerServer({
    required this.onButtonsChanged,
    required this.onStatusChanged,
    this.onInputCountChanged,
    this.port = 47531,
  });

  final int port;
  final void Function(Set<NesButton>) onButtonsChanged;
  final void Function(String) onStatusChanged;
  final void Function(int)? onInputCountChanged;
  ServerSocket? _server;
  Socket? _client;
  JsonLineBuffer? _buffer;
  Timer? _handshakeTimeout;
  Timer? _watchdog;
  String? _pairCode;
  String? _hostNonce;
  String? _sessionKey;
  bool _authenticated = false;
  int _badAttempts = 0;
  int _lastSequence = -1;
  int _inputsReceived = 0;
  DateTime _lastFrame = DateTime.now();
  List<String> addresses = const <String>[];

  bool get isListening => _server != null;
  bool get isConnected => _authenticated;
  String? get pairingCode => _pairCode;
  int get boundPort => _server?.port ?? port;
  int get inputsReceived => _inputsReceived;

  Future<void> start() async {
    if (_server != null) {
      return;
    }
    _pairCode = newPairingCode();
    _badAttempts = 0;
    _inputsReceived = 0;
    onInputCountChanged?.call(0);
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _server!.listen(
        _accept,
        onError: (Object _) => onStatusChanged('Local network listener failed.'),
      );
      addresses = await _localIpv4Addresses();
      onStatusChanged('Waiting for controller pairing');
    } on SocketException {
      _server = null;
      _pairCode = null;
      onStatusChanged('Could not open the local Wi-Fi port.');
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _pairCode = null;
    await server?.close();
    final client = _client;
    if (client != null) {
      _drop(client, status: 'Stopped');
    }
    _watchdog?.cancel();
    _watchdog = null;
    _handshakeTimeout?.cancel();
    _handshakeTimeout = null;
    addresses = const <String>[];
    _inputsReceived = 0;
    onInputCountChanged?.call(0);
    onButtonsChanged(const <NesButton>{});
    onStatusChanged('Stopped');
  }

  void _accept(Socket socket) {
    if (_client != null || _badAttempts >= 5 || _pairCode == null) {
      _send(socket, <String, Object>{'type': 'error', 'reason': 'busy'});
      socket.destroy();
      return;
    }
    _client = socket;
    _authenticated = false;
    _sessionKey = null;
    _lastSequence = -1;
    _hostNonce = newProtocolNonce();
    _lastFrame = DateTime.now();
    _buffer = JsonLineBuffer(
      onLine: (line) => _handleLine(socket, line),
      onInvalidFrame: () => _drop(socket, status: 'Invalid controller frame'),
    );
    _send(socket, <String, Object>{
      'type': 'challenge',
      'nonce': _hostNonce!,
      'protocol': 1,
    });
    _handshakeTimeout?.cancel();
    _handshakeTimeout = Timer(
      const Duration(seconds: 10),
      () => _drop(socket, status: 'Pairing timed out'),
    );
    socket.listen(
      (data) => _buffer?.add(data),
      onError: (Object _) => _drop(socket, status: 'Controller disconnected'),
      onDone: () => _drop(socket, status: 'Controller disconnected'),
      cancelOnError: true,
    );
    onStatusChanged('Pairing request received');
  }

  void _handleLine(Socket socket, String line) {
    if (!identical(socket, _client) || line.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        _drop(socket, status: 'Invalid controller message');
        return;
      }
      if (!_authenticated) {
        _authenticate(socket, decoded);
      } else {
        _acceptInput(socket, decoded);
      }
    } on FormatException {
      _drop(socket, status: 'Invalid controller message');
    } on TypeError {
      _drop(socket, status: 'Invalid controller message');
    }
  }

  void _authenticate(Socket socket, Map<String, dynamic> data) {
    final code = _pairCode;
    final hostNonce = _hostNonce;
    final clientNonce = data['clientNonce'];
    final proof = data['proof'];
    if (data['type'] != 'auth' ||
        code == null ||
        hostNonce == null ||
        !isProtocolNonce(clientNonce) ||
        !isHexSha256(proof)) {
      _badAttempts++;
      _send(socket, <String, Object>{
        'type': 'error',
        'reason': 'pairing_failed',
      });
      _drop(socket, status: 'Pairing failed');
      return;
    }

    if (!constantTimeEquals(
      proof as String,
      protocolMac(code, 'client|$hostNonce|$clientNonce'),
    )) {
      _badAttempts++;
      _send(socket, <String, Object>{
        'type': 'error',
        'reason': 'pairing_failed',
      });
      _drop(socket, status: 'Pairing failed');
      return;
    }

    _sessionKey = protocolMac(code, 'session|$hostNonce|$clientNonce');
    _authenticated = true;
    _lastFrame = DateTime.now();
    _lastSequence = -1;
    _handshakeTimeout?.cancel();
    _handshakeTimeout = null;
    _send(socket, <String, Object>{
      'type': 'accepted',
      'proof': protocolMac(
        _sessionKey!,
        'server|$hostNonce|$clientNonce',
      ),
    });
    onButtonsChanged(const <NesButton>{});
    onStatusChanged('Controller connected');
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_authenticated &&
          DateTime.now().difference(_lastFrame) >
              const Duration(seconds: 2)) {
        final active = _client;
        if (active != null) {
          _drop(active, status: 'Controller timed out');
        }
      }
    });
  }

  void _acceptInput(Socket socket, Map<String, dynamic> data) {
    final key = _sessionKey;
    if (data['type'] != 'input' || key == null) {
      _drop(socket, status: 'Invalid controller message');
      return;
    }
    final sequence = parseSequence(data['sequence']);
    final mask = parseButtonMask(data['mask']);
    final mac = data['mac'];
    if (!isHexSha256(mac)) {
      _drop(socket, status: 'Invalid controller message');
      return;
    }
    if (!constantTimeEquals(
      mac as String,
      protocolMac(key, 'input|$sequence|$mask'),
    )) {
      _drop(socket, status: 'Controller authentication failed');
      return;
    }
    if (sequence <= _lastSequence) {
      return;
    }
    _lastSequence = sequence;
    _lastFrame = DateTime.now();
    _inputsReceived++;
    onInputCountChanged?.call(_inputsReceived);
    onButtonsChanged(NesController.buttonsFromMask(mask));
  }

  void _drop(Socket socket, {required String status}) {
    if (identical(socket, _client)) {
      _client = null;
      _buffer?.close();
      _buffer = null;
      _handshakeTimeout?.cancel();
      _handshakeTimeout = null;
      _watchdog?.cancel();
      _watchdog = null;
      _sessionKey = null;
      _hostNonce = null;
      _authenticated = false;
      _lastSequence = -1;
      onButtonsChanged(const <NesButton>{});
      onStatusChanged(_server == null ? 'Stopped' : status);
    }
    socket.destroy();
  }

  static void _send(Socket socket, Map<String, Object> message) {
    try {
      socket.add(utf8.encode('${jsonEncode(message)}\n'));
    } on SocketException {
      socket.destroy();
    }
  }

  /// Re-scan active interfaces after a Wi-Fi switch without stopping the listener.
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
