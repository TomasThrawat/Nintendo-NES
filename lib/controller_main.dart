import 'package:flutter/material.dart';

import 'core/controller/nes_controller.dart';
import 'ui/remote_screen.dart';

void main() => runApp(const NesWifiControllerApp());

class NesWifiControllerApp extends StatelessWidget {
  const NesWifiControllerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'NES Wi-Fi Controller',
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
        home: const _ControllerHome(),
      );
}

class _ControllerHome extends StatelessWidget {
  const _ControllerHome();

  @override
  Widget build(BuildContext context) => RemoteScreen(
        mode: RemoteMode.controller,
        hostController: NesController(),
      );
}
