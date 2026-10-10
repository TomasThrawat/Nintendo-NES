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

/// The receiver opens directly, like WiFiPad. ROM loading remains optional.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _emulator = NesEmulator();
  String? _romName;
  String? _message;
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
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      _emulator.loadRom(bytes);
      if (!mounted) return;
      setState(() {
        _romName = file.name;
        _message =
            'ROM header validated. Gameplay is not available yet because PPU rendering, APU audio, and frame scheduling are incomplete.';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RemoteScreen(
        mode: RemoteMode.host,
        hostController: _emulator.controller1,
        onImportRom: _loading ? null : _importRom,
        romName: _romName,
        romMessage: _message,
      );
}
