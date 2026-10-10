import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller/nes_controller.dart';
import '../services/local_controller_client.dart';
import '../services/local_controller_server.dart';

enum RemoteMode { host, controller }

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({
    required this.mode,
    required this.hostController,
    super.key,
  });

  final RemoteMode mode;
  final NesController hostController;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  late final LocalControllerServer _server;
  late final LocalControllerClient _client;
  final _hostInput = TextEditingController();
  final _codeInput = TextEditingController();
  final Set<NesButton> _pressed = <NesButton>{};
  String _status = 'Receiver stopped';
  String? _pairCode;
  List<String> _addresses = const <String>[];
  int _inputsReceived = 0;
  bool _busy = false;
  bool _disposing = false;

  bool get _isHost => widget.mode == RemoteMode.host;

  @override
  void initState() {
    super.initState();
    _server = LocalControllerServer(
      onButtonsChanged: widget.hostController.setButtons,
      onStatusChanged: (status) {
        if (mounted && !_disposing) {
          setState(() => _status = status);
        }
      },
      onInputCountChanged: (count) {
        if (mounted && !_disposing) {
          setState(() => _inputsReceived = count);
        }
      },
    );
    _client = LocalControllerClient();
    if (!_isHost) {
      _status = 'Not connected';
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _server.stop();
    _client.disconnect();
    _hostInput.dispose();
    _codeInput.dispose();
    super.dispose();
  }

  Future<void> _startReceiver() async {
    setState(() => _busy = true);
    try {
      await _server.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _pairCode = _server.pairingCode;
        _addresses = _server.addresses;
        _inputsReceived = _server.inputsReceived;
      });
    } on Object catch (error) {
      if (mounted) {
        _showError(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopReceiver() async {
    await _server.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _pairCode = null;
      _addresses = const <String>[];
      _inputsReceived = 0;
    });
  }

  Future<void> _refreshAddresses() async {
    setState(() => _busy = true);
    try {
      final addresses = await _server.refreshAddresses();
      if (mounted) {
        setState(() => _addresses = addresses);
      }
    } on Object catch (error) {
      if (mounted) {
        _showError(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _connectController() async {
    setState(() => _busy = true);
    try {
      await _client.connect(
        host: _hostInput.text,
        pairingCode: _codeInput.text,
        onButtonsChanged: (_) {},
        onStatusChanged: (status) {
          if (mounted && !_disposing) {
            setState(() {
              _status = status;
              if (status != 'Connected') {
                _pressed.clear();
              }
            });
          }
        },
      );
      if (mounted) {
        setState(() {});
      }
    } on Object catch (error) {
      if (mounted) {
        _showError(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disconnectController() async {
    await _client.disconnect();
    if (mounted) {
      setState(_pressed.clear);
    }
  }

  void _setButton(NesButton button, bool down) {
    if (!_client.isConnected) {
      return;
    }
    if (down) {
      _pressed.add(button);
    } else {
      _pressed.remove(button);
    }
    _client.setButtons(_pressed);
    setState(() {});
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade900,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_isHost ? 'NES Receiver' : 'NES Wi-Fi Controller'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _statusPanel(),
            const SizedBox(height: 20),
            if (_isHost) ..._receiverControls() else ..._controllerControls(),
            const SizedBox(height: 24),
            const Divider(color: Colors.white24),
            Text(
              _isHost
                  ? 'This receiver passes authenticated NES button states directly to the emulator. It does not create a system-wide Android gamepad and does not need Shizuku.'
                  : 'Connect to the NES Receiver shown on the other device. Only NES D-pad, A, B, Start, and Select inputs are sent. Both devices must use the same local Wi-Fi; internet is not required.',
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPanel() {
    final active = _isHost ? _server.isListening : _client.isConnected;
    final connected = _isHost ? _server.isConnected : _client.isConnected;
    final title = connected
        ? 'Controller connected'
        : active
            ? 'Waiting for controller'
            : _status;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white38),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            connected ? Icons.wifi : active ? Icons.wifi_tethering : Icons.wifi_off,
            color: Colors.white,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _isHost ? 'RECEIVER STATUS' : 'CONTROLLER STATUS',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_isHost && _server.isListening) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '$_inputsReceived accepted input frames',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _receiverControls() => <Widget>[
        if (!_server.isListening)
          FilledButton(
            onPressed: _busy ? null : _startReceiver,
            style: _primary(),
            child: const Text('Start NES receiver'),
          )
        else ...<Widget>[
          const Text(
            'Receiver address',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          if (_addresses.isEmpty)
            const Text(
              'No local IPv4 address found. Connect this device to Wi-Fi, then refresh addresses.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            )
          else
            for (final address in _addresses)
              SelectableText(
                '$address:${_server.boundPort}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refreshAddresses,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Wi-Fi address'),
            style: _outline(),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pairing code',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  _pairCode ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy pairing code',
                onPressed: _pairCode == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: _pairCode!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pairing code copied')),
                        );
                      },
                icon: const Icon(Icons.copy, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter this code with the receiver IP on the controller device. Stop the receiver to invalidate the code.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _busy ? null : _stopReceiver,
            style: _outline(),
            child: const Text('Stop receiver and release all buttons'),
          ),
        ],
      ];

  List<Widget> _controllerControls() => <Widget>[
        TextField(
          controller: _hostInput,
          keyboardType: TextInputType.number,
          autocorrect: false,
          style: const TextStyle(color: Colors.white),
          decoration: _input('Receiver IPv4 address'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeInput,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(color: Colors.white, letterSpacing: 1.4),
          decoration: _input('16-character pairing code'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy || _client.isConnected ? null : _connectController,
          style: _primary(),
          child: const Text('Connect to NES receiver'),
        ),
        if (_client.isConnected) ...<Widget>[
          const SizedBox(height: 22),
          const Text(
            'NES controls · hold buttons to press',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          Center(
            child: Column(
              children: <Widget>[
                _touch('UP', NesButton.up),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _touch('LEFT', NesButton.left),
                    const SizedBox(width: 10),
                    _touch('DOWN', NesButton.down),
                    const SizedBox(width: 10),
                    _touch('RIGHT', NesButton.right),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _touch('B', NesButton.b),
              _touch('A', NesButton.a),
              _touch('SELECT', NesButton.select),
              _touch('START', NesButton.start),
            ],
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: _disconnectController,
            style: _outline(),
            child: const Text('Disconnect'),
          ),
        ],
      ];

  Widget _touch(String label, NesButton button) {
    final active = _pressed.contains(button);
    return GestureDetector(
      onTapDown: (_) => _setButton(button, true),
      onTapUp: (_) => _setButton(button, false),
      onTapCancel: () => _setButton(button, false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: label.length > 5 ? 94 : 70,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.black,
          border: Border.all(color: Colors.white, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white54),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
      );

  ButtonStyle _primary() => FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(48),
      );

  ButtonStyle _outline() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        minimumSize: const Size.fromHeight(48),
      );
}
