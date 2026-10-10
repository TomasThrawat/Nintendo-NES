import 'package:flutter/material.dart';
import 'ui/remote_screen.dart';

void main() => runApp(const GamepadControllerApp());

class GamepadControllerApp extends StatelessWidget {
  const GamepadControllerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'NES-Style Wi-Fi Controller',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.white, onPrimary: Colors.black, surface: Colors.black, onSurface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white),
        ),
        home: const RemoteScreen(mode: RemoteMode.controller),
      );
}
