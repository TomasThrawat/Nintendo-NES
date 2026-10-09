import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'core/emulator.dart';
import 'ui/remote_screen.dart';

void main() => runApp(const NintendoNesApp());

class NintendoNesApp extends StatelessWidget {
  const NintendoNesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Nintendo NES Receiver',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            surface: Colors.black,
            onSurface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
        ),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _emulator = NesEmulator();
  String? _romName, _message;
  bool _loading = false;

  Future<void> _importRom() async {
    setState(() => _loading = true);
    try {
      const romType = XTypeGroup(
        label: 'NES ROM',
        extensions: <String>['nes'],
      );
      final file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[romType],
      );
      if (file == null) {
        return;
      }
      final Uint8List bytes = await file.readAsBytes();
      _emulator.loadRom(bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _romName = file.name;
        _message =
            'ROM header validated and CPU reset completed. Gameplay is not available yet: PPU rendering, APU audio, and frame scheduling are still incomplete.';
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openReceiver() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteScreen(
          mode: RemoteMode.host,
          hostController: _emulator.controller1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rom = _emulator.rom;
    return Scaffold(
      appBar: AppBar(title: const Text('Nintendo NES / Famicom')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const Icon(Icons.videogame_asset, size: 64, color: Colors.white),
            const SizedBox(height: 16),
            const Text(
              'Dart emulator core',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 8),
            const Text(
              'Independent Flutter/Dart NES project. No commercial ROMs are bundled; import a game file you are legally entitled to use.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _loading ? null : _importRom,
              icon: const Icon(Icons.folder_open),
              label: Text(_loading ? 'Reading ROM…' : 'Import .nes ROM'),
            ),
            if (_romName != null && rom != null) ...<Widget>[
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              Text(
                _romName!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${rom.isNes2 ? 'NES 2.0' : 'iNES'} · Mapper ${rom.mapper} · ${rom.prgRom.length ~/ 1024} KiB PRG · ${rom.chrRom.isEmpty ? 'CHR RAM' : '${rom.chrRom.length ~/ 1024} KiB CHR'}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            if (_message != null) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _message!,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 26),
            const Text(
              'Wi-Fi receiver',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'Run this app on the device that will host the emulator. Open the receiver to display its local address, pair the dedicated controller app, and receive NES-only button input.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openReceiver,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Open NES receiver'),
              style: _outline(),
            ),
            const SizedBox(height: 24),
            const Divider(color: Colors.white24),
            const Text(
              'Implemented: iNES/NES 2.0 header parsing, NROM mapping, official 6502 instruction core, NES serial controller input, and authenticated local Wi-Fi transport. Not implemented: PPU rendering, APU audio, frame timing, battery save persistence, and save states.',
              style: TextStyle(color: Colors.white54, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _outline() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        minimumSize: const Size.fromHeight(48),
      );
}
