import 'dart:async';
import 'dart:io';

import '../core/controller/nes_controller.dart';
import 'remote_protocol.dart';

/// WiFiPad-style IP-only UDP sender for NES input updates at ~60 Hz.
class LocalControllerClient {
  RawDatagramSocket? _socket;
  InternetAddress? _targetAddress;
  Timer? _sendTimer;
  Timer? _watchdog;
  Completer<void>? _firstAck;
  void Function(String)? _onStatus;
  void Function(Set<NesButton>)? _onButtons;
  int _targetPort = nesWifiPort;
  int _sequence = 0;
  int _lastAckSequence = -1;
  int _mask = 0;
  bool _running = false;
  bool _connected = false;
  bool _closing = false;
  String _status = 'Disconnected';
  DateTime _lastAckAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isConnected => _connected;

  Future<void> connect({
    required String host,
    required void Function(Set<NesButton>) onButtonsChanged,
    required void Function(String) onStatusChanged,
    int port = nesWifiPort,
  }) async {
    await disconnect();
    final address = InternetAddress.tryParse(host.trim());
    if (address == null || address.type != InternetAddressType.IPv4) {
      throw const FormatException('Enter the receiver IPv4 address.');
    }

    _targetAddress = address;
    _targetPort = port;
    _onButtons = onButtonsChanged;
    _onStatus = onStatusChanged;
    _closing = false;
    _connected = false;
    _mask = 0;
    _sequence = 0;
    _lastAckSequence = -1;
    _notify('Connecting to NES receiver');

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    _socket = socket;
    socket.readEventsEnabled = true;
    socket.writeEventsEnabled = false;
    socket.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          _receiveAcks();
        }
      },
      onError: (Object _) => _socketFailed(),
      onDone: _socketFailed,
      cancelOnError: true,
    );

    final firstAck = Completer<void>();
    _firstAck = firstAck;
    _running = true;
    _sendInput();
    _sendTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _sendInput(),
    );
    _watchdog = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _checkAckTimeout(),
    );

    try {
      await firstAck.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw const SocketException(
          'No receiver response. Check both devices are on the same Wi-Fi and verify the IP address.',
        ),
      );
    } on Object {
      await disconnect();
      rethrow;
    }
  }

  void setButtons(Iterable<NesButton> buttons) {
    _mask = NesController.maskFor(buttons);
    if (_running) {
      _sendInput();
    }
  }

  Future<void> disconnect() async {
    _closing = true;
    _sendTimer?.cancel();
    _sendTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
    final socket = _socket;
    if (socket != null && _running) {
      _mask = 0;
      // Several final all-buttons-up datagrams reduce the chance of a lost
      // release packet. The receiver also has a 750 ms watchdog failsafe.
      for (var i = 0; i < 3; i++) {
        _sendInput();
      }
    }
    _running = false;
    _connected = false;
    _mask = 0;
    _socket = null;
    socket?.close();
    _targetAddress = null;
    _lastAckSequence = -1;
    _onButtons?.call(const <NesButton>{});
    _notify('Disconnected');
    _closing = false;
  }

  void _sendInput() {
    final socket = _socket;
    final target = _targetAddress;
    if (!_running || socket == null || target == null) {
      return;
    }
    _sequence = (_sequence + 1) & 0xffffffff;
    try {
      socket.send(
        encodeNesInputPacket(
          sequence: _sequence,
          mask: _mask,
        ),
        target,
        _targetPort,
      );
    } on SocketException {
      _socketFailed();
    } on FormatException {
      _socketFailed();
    }
  }

  void _receiveAcks() {
    final socket = _socket;
    final target = _targetAddress;
    if (socket == null || target == null) {
      return;
    }
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) {
        return;
      }
      if (datagram.address.address != target.address ||
          datagram.port != _targetPort ||
          !isNesAckPacket(datagram.data) ||
          !isValidNesDatagram(datagram.data)) {
        continue;
      }
      final sequence = readNesSequence(datagram.data);
      if (isNewerNesSequence(sequence, _sequence)) {
        continue;
      }
      final age = (_sequence - sequence) & 0xffffffff;
      if (age > 120) {
        continue;
      }
      if (_lastAckSequence >= 0 &&
          !isNewerNesSequence(sequence, _lastAckSequence)) {
        continue;
      }
      _lastAckSequence = sequence;
      _lastAckAt = DateTime.now();
      if (!_connected) {
        _connected = true;
        _notify('Connected to NES receiver');
      }
      final firstAck = _firstAck;
      if (firstAck != null && !firstAck.isCompleted) {
        firstAck.complete();
      }
    }
  }

  void _checkAckTimeout() {
    if (!_running ||
        !_connected ||
        DateTime.now().difference(_lastAckAt) <
            const Duration(milliseconds: 1500)) {
      return;
    }
    _connected = false;
    _mask = 0;
    _onButtons?.call(const <NesButton>{});
    _notify('Receiver connection lost');
  }

  void _socketFailed() {
    if (_closing || !_running) {
      return;
    }
    _running = false;
    _connected = false;
    _mask = 0;
    _sendTimer?.cancel();
    _sendTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
    _socket?.close();
    _socket = null;
    _onButtons?.call(const <NesButton>{});
    _notify('Wi-Fi socket closed');
    final firstAck = _firstAck;
    if (firstAck != null && !firstAck.isCompleted) {
      firstAck.completeError(const SocketException('Wi-Fi socket closed.'));
    }
  }

  void _notify(String value) {
    if (_status == value) {
      return;
    }
    _status = value;
    _onStatus?.call(value);
  }
}
