import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller/nes_controller.dart';
import '../services/control_layout.dart';
import '../services/local_controller_client.dart';
import '../services/local_controller_server.dart';

enum RemoteMode { host, controller }

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({
    required this.mode,
    required this.hostController,
    this.onImportRom,
    this.romName,
    this.romMessage,
    super.key,
  });

  final RemoteMode mode;
  final NesController hostController;
  final VoidCallback? onImportRom;
  final String? romName;
  final String? romMessage;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  late final LocalControllerServer _server;
  late final LocalControllerClient _client;
  final _hostInput = TextEditingController();
  final Set<NesButton> _pressed = <NesButton>{};
  Map<NesButton, ControlPlacement> _placements =
      Map<NesButton, ControlPlacement>.of(ControlLayoutStore.defaults);
  NesButton _selectedButton = NesButton.up;
  String _status = 'Receiver stopped';
  List<String> _addresses = const <String>[];
  int _inputsReceived = 0;
  bool _busy = false;
  bool _editing = false;
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
      _status = 'Enter receiver IP address';
    }
  }

  @override
  void dispose() {
    _disposing = true;
    unawaited(_server.stop());
    unawaited(_client.disconnect());
    _hostInput.dispose();
    if (!_isHost) {
      unawaited(
        SystemChrome.setPreferredOrientations(
          const <DeviceOrientation>[DeviceOrientation.portraitUp],
        ),
      );
    }
    super.dispose();
  }

  Future<void> _startReceiver() async {
    setState(() => _busy = true);
    try {
      await _server.start();
      if (!mounted) return;
      setState(() {
        _addresses = _server.addresses;
        _inputsReceived = _server.inputsReceived;
      });
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopReceiver() async {
    await _server.stop();
    if (!mounted) return;
    setState(() {
      _addresses = const <String>[];
      _inputsReceived = 0;
    });
  }

  Future<void> _refreshAddresses() async {
    setState(() => _busy = true);
    try {
      final addresses = await _server.refreshAddresses();
      if (mounted) setState(() => _addresses = addresses);
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectController() async {
    setState(() => _busy = true);
    try {
      await _client.connect(
        host: _hostInput.text,
        onButtonsChanged: (_) {},
        onStatusChanged: (status) {
          if (mounted && !_disposing) {
            setState(() {
              _status = status;
              if (status != 'Connected to NES receiver') _pressed.clear();
            });
          }
        },
      );
      if (!mounted) return;
      await SystemChrome.setPreferredOrientations(
        const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
      final savedLayout = await ControlLayoutStore.load();
      if (mounted) {
        setState(() {
          _placements = savedLayout;
          _editing = false;
          _status = 'Connected to NES receiver';
        });
      }
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectController() async {
    await _client.disconnect();
    await SystemChrome.setPreferredOrientations(
      const <DeviceOrientation>[DeviceOrientation.portraitUp],
    );
    if (mounted) {
      setState(() {
        _pressed.clear();
        _editing = false;
        _status = 'Disconnected';
      });
    }
  }

  void _setButton(NesButton button, bool down) {
    if (!_client.isConnected || _editing) return;
    if (down) {
      _pressed.add(button);
    } else {
      _pressed.remove(button);
    }
    _client.setButtons(_pressed);
    setState(() {});
  }

  void _moveButton(
    NesButton button,
    Offset delta,
    double width,
    double height,
  ) {
    final current = _placements[button] ?? ControlLayoutStore.defaults[button]!;
    setState(() {
      _selectedButton = button;
      _placements[button] = current.copyWith(
        x: current.x + delta.dx / width,
        y: current.y + delta.dy / height,
      );
    });
  }

  Future<void> _saveButton(NesButton button) async {
    final placement = _placements[button];
    if (placement != null) await ControlLayoutStore.save(button, placement);
  }

  Future<void> _resetControlLayout() async {
    await ControlLayoutStore.reset();
    if (!mounted) return;
    setState(() {
      _placements = Map<NesButton, ControlPlacement>.of(
        ControlLayoutStore.defaults,
      );
      _selectedButton = NesButton.up;
    });
  }

  Future<void> _saveSelectedPlacement(ControlPlacement placement) async {
    setState(() => _placements[_selectedButton] = placement);
    await _saveButton(_selectedButton);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade900),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectedController = !_isHost && _client.isConnected;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: connectedController
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(_isHost ? 'Nintendo NES Receiver' : 'NES Wi-Fi Controller'),
              actions: <Widget>[
                if (_isHost && widget.onImportRom != null)
                  IconButton(
                    tooltip: 'Import NES ROM',
                    onPressed: _busy ? null : widget.onImportRom,
                    icon: const Icon(Icons.folder_open),
                  ),
              ],
            ),
      body: SafeArea(
        child: _isHost
            ? _receiverBody()
            : connectedController
                ? _gamepadLayout()
                : _controllerConnectBody(),
      ),
    );
  }

  Widget _receiverBody() => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _statusPanel(),
          const SizedBox(height: 20),
          ..._receiverControls(),
          if (widget.romName != null) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              'Loaded ROM: ' + widget.romName!,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
          if (widget.romMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              widget.romMessage!,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(color: Colors.white24),
          const Text(
            'Enter the receiver IP in the NES controller app. Both devices must be on the same trusted Wi-Fi network. No pairing code or internet is required.',
            style: TextStyle(color: Colors.white70, height: 1.45),
          ),
        ],
      );

  Widget _controllerConnectBody() => ListView(
        padding: const EdgeInsets.all(22),
        children: <Widget>[
          const Icon(Icons.gamepad, size: 62, color: Colors.white),
          const SizedBox(height: 18),
          const Text(
            'Connect to your NES receiver',
            style: TextStyle(color: Colors.white, fontSize: 23),
          ),
          const SizedBox(height: 10),
          const Text(
            'Enter the receiver IPv4 address shown on the other device. The port is detected automatically. No pairing code is needed.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 26),
          TextField(
            controller: _hostInput,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: _input('Receiver IPv4 address'),
            onSubmitted: (_) {
              if (!_busy) _connectController();
            },
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _connectController,
            style: _primary(),
            icon: const Icon(Icons.wifi),
            label: Text(_busy ? 'Connecting…' : 'Connect and open controller'),
          ),
          const SizedBox(height: 12),
          Text(
            _status,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      );

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
            connected
                ? Icons.wifi
                : active
                    ? Icons.wifi_tethering
                    : Icons.wifi_off,
            color: Colors.white,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'RECEIVER STATUS',
                  style: TextStyle(
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
                if (_server.isListening) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    _inputsReceived.toString() + ' received NES input frames',
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
          FilledButton.icon(
            onPressed: _busy ? null : _startReceiver,
            style: _primary(),
            icon: const Icon(Icons.play_arrow),
            label: Text(_busy ? 'Starting receiver…' : 'Start NES receiver'),
          )
        else ...<Widget>[
          const Text(
            'Receiver IP address',
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
                address,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
          const SizedBox(height: 8),
          const Text(
            'UDP port: 27191 (set automatically in the controller app)',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refreshAddresses,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Wi-Fi address'),
            style: _outline(),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _stopReceiver,
            style: _outline(),
            child: const Text('Stop receiver and release all buttons'),
          ),
        ],
        if (widget.onImportRom != null) ...<Widget>[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : widget.onImportRom,
            icon: const Icon(Icons.folder_open),
            label: Text(widget.romName == null ? 'Import .nes ROM' : 'Change .nes ROM'),
            style: _outline(),
          ),
        ],
      ];

  Widget _gamepadLayout() => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final children = <Widget>[
            Positioned(
              left: 4,
              right: 4,
              top: 0,
              height: 44,
              child: Container(
                color: Colors.black,
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.wifi, color: Colors.white),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Connected to ' + _hostInput.text.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _editing = !_editing),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      icon: Icon(_editing ? Icons.check : Icons.edit),
                      label: Text(_editing ? 'Done' : 'Edit controls'),
                    ),
                    IconButton(
                      tooltip: 'Disconnect',
                      onPressed: _disconnectController,
                      icon: const Icon(Icons.link_off, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ];

          if (_editing) {
            final selected =
                _placements[_selectedButton] ?? ControlLayoutStore.defaults[_selectedButton]!;
            children.add(
              Positioned(
                left: 10,
                right: 10,
                top: 46,
                height: 88,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.white54),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            Text(
                              'Edit ' + _selectedButton.name.toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Slider(
                                min: 0.60,
                                max: 1.60,
                                divisions: 10,
                                value: selected.scale.clamp(0.60, 1.60).toDouble(),
                                onChanged: (value) {
                                  setState(() {
                                    _placements[_selectedButton] =
                                        selected.copyWith(scale: value);
                                  });
                                },
                                onChangeEnd: (value) {
                                  unawaited(_saveButton(_selectedButton));
                                },
                              ),
                            ),
                            const Text('Show', style: TextStyle(color: Colors.white)),
                            Checkbox(
                              value: selected.visible,
                              activeColor: Colors.white,
                              checkColor: Colors.black,
                              onChanged: (value) {
                                if (value == null) return;
                                final button = _selectedButton;
                                unawaited(
                                  _saveSelectedPlacement(
                                    selected.copyWith(visible: value),
                                  ),
                                );
                                setState(() => _selectedButton = button);
                              },
                            ),
                            IconButton(
                              tooltip: 'Reset button positions',
                              onPressed: _resetControlLayout,
                              icon: const Icon(Icons.restart_alt, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        'Drag any button to move it. Select a button to resize or hide it.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          for (final button in NesButton.values) {
            final placement =
                _placements[button] ?? ControlLayoutStore.defaults[button]!;
            if (!placement.visible && !_editing) continue;
            final buttonHeight = _buttonHeight(placement, width, height);
            final buttonWidth = _buttonWidth(button, buttonHeight);
            final left = (placement.x * width - buttonWidth / 2)
                .clamp(0.0, math.max(0.0, width - buttonWidth))
                .toDouble();
            final top = (placement.y * height - buttonHeight / 2)
                .clamp(0.0, math.max(0.0, height - buttonHeight))
                .toDouble();
            children.add(
              Positioned(
                left: left,
                top: top,
                width: buttonWidth,
                height: buttonHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _editing ? () => setState(() => _selectedButton = button) : null,
                  onPanStart: _editing ? (_) => setState(() => _selectedButton = button) : null,
                  onPanUpdate: _editing
                      ? (details) => _moveButton(button, details.delta, width, height)
                      : null,
                  onPanEnd: _editing ? (_) => unawaited(_saveButton(button)) : null,
                  onTapDown: _editing ? null : (_) => _setButton(button, true),
                  onTapUp: _editing ? null : (_) => _setButton(button, false),
                  onTapCancel: _editing ? null : () => _setButton(button, false),
                  child: Opacity(
                    opacity: _editing && !placement.visible ? 0.28 : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 60),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _pressed.contains(button) && !_editing
                            ? Colors.white
                            : Colors.black,
                        border: Border.all(
                          color: _editing && _selectedButton == button
                              ? Colors.white
                              : Colors.white70,
                          width: _editing && _selectedButton == button ? 3 : 1.6,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _buttonLabel(button),
                        maxLines: 1,
                        style: TextStyle(
                          color: _pressed.contains(button) && !_editing
                              ? Colors.black
                              : Colors.white,
                          fontSize: math.max(12, buttonHeight * 0.22),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return Stack(clipBehavior: Clip.hardEdge, children: children);
        },
      );

  double _buttonHeight(ControlPlacement placement, double width, double height) =>
      (math.min(width, height) * 0.15 * placement.scale)
          .clamp(48.0, 92.0)
          .toDouble();

  double _buttonWidth(NesButton button, double height) {
    if (button == NesButton.select || button == NesButton.start) {
      return math.max(78.0, height * 1.35).toDouble();
    }
    return height;
  }

  String _buttonLabel(NesButton button) {
    switch (button) {
      case NesButton.a:
        return 'A';
      case NesButton.b:
        return 'B';
      case NesButton.select:
        return 'SELECT';
      case NesButton.start:
        return 'START';
      case NesButton.up:
        return '▲';
      case NesButton.down:
        return '▼';
      case NesButton.left:
        return '◀';
      case NesButton.right:
        return '▶';
    }
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
        minimumSize: const Size.fromHeight(52),
      );

  ButtonStyle _outline() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        minimumSize: const Size.fromHeight(48),
      );
}
