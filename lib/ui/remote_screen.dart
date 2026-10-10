import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller/gamepad_state.dart';
import '../services/control_layout.dart';
import '../services/local_controller_client.dart';
import '../services/local_controller_server.dart';
import '../services/system_gamepad_bridge.dart';

enum RemoteMode { receiver, controller }

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({required this.mode, super.key});
  final RemoteMode mode;
  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  late final LocalControllerServer _server;
  late final LocalControllerClient _client;
  final TextEditingController _ip = TextEditingController();
  final Set<GamepadButton> _pressed = <GamepadButton>{};
  Map<GamepadButton, ControlPlacement> _placements =
      Map<GamepadButton, ControlPlacement>.of(ControlLayoutStore.defaults);
  GamepadButton _selected = GamepadButton.up;
  String _status = 'Receiver stopped';
  List<String> _addresses = const <String>[];
  int _received = 0;
  bool _busy = false;
  bool _editing = false;
  bool _disposing = false;

  bool get _isReceiver => widget.mode == RemoteMode.receiver;
  bool get _connectedController => !_isReceiver && _client.isConnected;

  @override
  void initState() {
    super.initState();
    _server = LocalControllerServer(
      systemGamepadEnabled: _isReceiver,
      onButtonsChanged: _forwardButtons,
      onStatusChanged: (value) {
        if (mounted && !_disposing) setState(() => _status = value);
      },
      onInputCountChanged: (value) {
        if (mounted && !_disposing) setState(() => _received = value);
      },
    );
    _client = LocalControllerClient();
    if (!_isReceiver) _status = 'Enter receiver IP address';
  }

  void _forwardButtons(Set<GamepadButton> buttons) {
    if (!_isReceiver) return;
    unawaited(() async {
      try {
        await SystemGamepadBridge.setButtons(buttons);
      } on Object catch (error) {
        if (mounted && !_disposing) setState(() => _status = 'Gamepad input forwarding failed: $error');
      }
    }());
  }

  @override
  void dispose() {
    _disposing = true;
    unawaited(_server.stop());
    unawaited(_client.disconnect());
    _ip.dispose();
    if (!_isReceiver) {
      unawaited(SystemChrome.setPreferredOrientations(
        const <DeviceOrientation>[DeviceOrientation.portraitUp],
      ));
    }
    super.dispose();
  }

  Future<void> _startReceiver() async {
    setState(() => _busy = true);
    try {
      await _server.start();
      if (mounted) setState(() {
        _addresses = _server.addresses;
        _received = _server.inputsReceived;
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
    setState(() { _addresses = const <String>[]; _received = 0; });
  }

  Future<void> _refreshAddresses() async {
    setState(() => _busy = true);
    try {
      final result = await _server.refreshAddresses();
      if (mounted) setState(() => _addresses = result);
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await _client.connect(
        host: _ip.text,
        onButtonsChanged: (_) {},
        onStatusChanged: (value) {
          if (mounted && !_disposing) {
            setState(() { _status = value; if (value != 'Connected to gamepad receiver') _pressed.clear(); });
          }
        },
      );
      if (!mounted) return;
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
      ]);
      final saved = await ControlLayoutStore.load();
      if (mounted) setState(() {
        _placements = saved;
        _editing = false;
        _status = 'Connected to gamepad receiver';
      });
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await _client.disconnect();
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[DeviceOrientation.portraitUp]);
    if (mounted) setState(() { _pressed.clear(); _editing = false; _status = 'Disconnected'; });
  }

  void _setButton(GamepadButton button, bool down) {
    if (!_client.isConnected || _editing) return;
    if (down) { _pressed.add(button); } else { _pressed.remove(button); }
    _client.setButtons(_pressed);
    setState(() {});
  }

  void _moveButton(GamepadButton button, Offset delta, double width, double height) {
    final current = _placements[button] ?? ControlLayoutStore.defaults[button]!;
    setState(() {
      _selected = button;
      _placements[button] = current.copyWith(
        x: current.x + delta.dx / width,
        y: current.y + delta.dy / height,
      );
    });
  }

  Future<void> _saveButton(GamepadButton button) async {
    final placement = _placements[button];
    if (placement != null) await ControlLayoutStore.save(button, placement);
  }

  Future<void> _saveSelected(ControlPlacement placement) async {
    setState(() => _placements[_selected] = placement);
    await _saveButton(_selected);
  }

  Future<void> _resetLayout() async {
    await ControlLayoutStore.reset();
    if (!mounted) return;
    setState(() {
      _placements = Map<GamepadButton, ControlPlacement>.of(ControlLayoutStore.defaults);
      _selected = GamepadButton.up;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade900),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: _connectedController ? null : AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(_isReceiver ? 'NES-Style Gamepad Receiver' : 'NES-Style Wi-Fi Controller'),
    ),
    body: SafeArea(
      child: _isReceiver
          ? _receiverBody()
          : _connectedController
              ? _controllerBody()
              : _connectBody(),
    ),
  );

  Widget _receiverBody() => ListView(
    padding: const EdgeInsets.all(20),
    children: <Widget>[
      _statusPanel(),
      const SizedBox(height: 20),
      if (!_server.isListening)
        FilledButton.icon(
          onPressed: _busy ? null : _startReceiver,
          style: _primary(),
          icon: const Icon(Icons.play_arrow),
          label: Text(_busy ? 'Starting receiver…' : 'Start gamepad receiver'),
        )
      else ...<Widget>[
        const Text('Receiver IP address', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        if (_addresses.isEmpty)
          const Text('No local IPv4 address found. Connect this device to Wi-Fi, then refresh addresses.',
              style: TextStyle(color: Colors.white70))
        else
          for (final address in _addresses)
            SelectableText(address, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('UDP port: 27191 (automatic on the phone)', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _busy ? null : _refreshAddresses,
            icon: const Icon(Icons.refresh), label: const Text('Refresh Wi-Fi address'), style: _outline()),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _busy ? null : _stopReceiver,
            style: _outline(), child: const Text('Stop receiver and release gamepad')),
      ],
      const SizedBox(height: 24),
      const Divider(color: Colors.white24),
      const Text(
        'The TV needs Shizuku running with Wireless debugging. When you start the receiver, grant its Shizuku permission so it can register a system-wide virtual gamepad. A plain UDP receiver cannot control other apps without this privileged input bridge.',
        style: TextStyle(color: Colors.white70, height: 1.45),
      ),
    ],
  );

  Widget _statusPanel() {
    final active = _isReceiver ? _server.isListening : _client.isConnected;
    final connected = _isReceiver ? _server.isConnected : _client.isConnected;
    final title = connected ? 'Controller connected' : active ? _status : _status;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white38),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: <Widget>[
        Icon(connected ? Icons.wifi : active ? Icons.wifi_tethering : Icons.wifi_off,
            color: Colors.white, size: 30),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Text('RECEIVER STATUS', style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 5),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          if (_server.isListening) ...<Widget>[
            const SizedBox(height: 4),
            Text('$_received received gamepad frames', style: const TextStyle(color: Colors.white70)),
          ],
        ])),
      ]),
    );
  }

  Widget _connectBody() => ListView(
    padding: const EdgeInsets.all(22),
    children: <Widget>[
      const Icon(Icons.gamepad, size: 62, color: Colors.white),
      const SizedBox(height: 18),
      const Text('Connect to your gamepad receiver', style: TextStyle(color: Colors.white, fontSize: 23)),
      const SizedBox(height: 10),
      const Text('Enter the receiver IPv4 address shown on the TV. The port is automatic; no pairing code is required.',
          style: TextStyle(color: Colors.white70, height: 1.4)),
      const SizedBox(height: 26),
      TextField(
        controller: _ip,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        decoration: _input('Receiver IPv4 address'),
        onSubmitted: (_) { if (!_busy) unawaited(_connect()); },
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy ? null : _connect,
        style: _primary(),
        icon: const Icon(Icons.wifi),
        label: Text(_busy ? 'Connecting…' : 'Connect and open controller'),
      ),
      const SizedBox(height: 12),
      Text(_status, style: const TextStyle(color: Colors.white70)),
    ],
  );

  Widget _controllerBody() => LayoutBuilder(builder: (context, constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final widgets = <Widget>[
      Positioned(
        left: 4, right: 4, top: 0, height: 44,
        child: ColoredBox(color: Colors.black, child: Row(children: <Widget>[
          const Icon(Icons.wifi, color: Colors.white),
          const SizedBox(width: 7),
          Flexible(child: Text('Connected to ${_ip.text.trim()}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
          TextButton.icon(
            onPressed: () => setState(() => _editing = !_editing),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: Icon(_editing ? Icons.check : Icons.edit),
            label: Text(_editing ? 'Done' : 'Edit controls'),
          ),
          IconButton(tooltip: 'Disconnect', onPressed: _disconnect,
              icon: const Icon(Icons.link_off, color: Colors.white)),
        ])),
      ),
    ];
    if (_editing) {
      final selected = _placements[_selected] ?? ControlLayoutStore.defaults[_selected]!;
      widgets.add(Positioned(
        left: 10, right: 10, top: 46, height: 88,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white54),
              borderRadius: BorderRadius.circular(10)),
          child: Column(children: <Widget>[
            Expanded(child: Row(children: <Widget>[
              Text('Edit ${_selected.name.toUpperCase()}', style: const TextStyle(color: Colors.white)),
              const SizedBox(width: 8),
              Expanded(child: Slider(
                min: 0.60, max: 1.60, divisions: 10,
                value: selected.scale.clamp(0.60, 1.60).toDouble(),
                onChanged: (value) => setState(() {
                  _placements[_selected] = selected.copyWith(scale: value);
                }),
                onChangeEnd: (_) => unawaited(_saveButton(_selected)),
              )),
              const Text('Show', style: TextStyle(color: Colors.white)),
              Checkbox(value: selected.visible, activeColor: Colors.white, checkColor: Colors.black,
                onChanged: (value) {
                  if (value != null) unawaited(_saveSelected(selected.copyWith(visible: value)));
                }),
              IconButton(tooltip: 'Reset button positions', onPressed: _resetLayout,
                  icon: const Icon(Icons.restart_alt, color: Colors.white)),
            ])),
            const Text('Drag any button to move it. Select a button to resize or hide it.',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ),
      ));
    }
    for (final button in GamepadButton.values) {
      final placement = _placements[button] ?? ControlLayoutStore.defaults[button]!;
      if (!placement.visible && !_editing) continue;
      final h = (math.min(width, height) * 0.15 * placement.scale).clamp(48.0, 92.0).toDouble();
      final w = button == GamepadButton.select || button == GamepadButton.start
          ? math.max(78.0, h * 1.35).toDouble() : h;
      final left = (placement.x * width - w / 2).clamp(0.0, math.max(0.0, width - w)).toDouble();
      final top = (placement.y * height - h / 2).clamp(0.0, math.max(0.0, height - h)).toDouble();
      widgets.add(Positioned(
        left: left, top: top, width: w, height: h,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _editing ? () => setState(() => _selected = button) : null,
          onPanStart: _editing ? (_) => setState(() => _selected = button) : null,
          onPanUpdate: _editing ? (d) => _moveButton(button, d.delta, width, height) : null,
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
                color: _pressed.contains(button) && !_editing ? Colors.white : Colors.black,
                border: Border.all(
                  color: _editing && _selected == button ? Colors.white : Colors.white70,
                  width: _editing && _selected == button ? 3 : 1.6,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_label(button), maxLines: 1, style: TextStyle(
                color: _pressed.contains(button) && !_editing ? Colors.black : Colors.white,
                fontSize: math.max(12.0, h * 0.22), fontWeight: FontWeight.bold,
              )),
            ),
          ),
        ),
      ));
    }
    return Stack(clipBehavior: Clip.hardEdge, children: widgets);
  });

  String _label(GamepadButton button) => switch (button) {
    GamepadButton.a => 'A',
    GamepadButton.b => 'B',
    GamepadButton.select => 'SELECT',
    GamepadButton.start => 'START',
    GamepadButton.up => '▲',
    GamepadButton.down => '▼',
    GamepadButton.left => '◀',
    GamepadButton.right => '▶',
  };

  InputDecoration _input(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white54),
    enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
  );

  ButtonStyle _primary() => FilledButton.styleFrom(
    backgroundColor: Colors.white, foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(52),
  );

  ButtonStyle _outline() => OutlinedButton.styleFrom(
    foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54),
    minimumSize: const Size.fromHeight(48),
  );
}
