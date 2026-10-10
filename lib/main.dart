import 'package:flutter/material.dart';
import 'ui/remote_screen.dart';

void main() => runApp(const GamepadReceiverApp());

class GamepadReceiverApp extends StatelessWidget {
  const GamepadReceiverApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'NES-Style Gamepad Receiver',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.white, onPrimary: Colors.black, surface: Colors.black, onSurface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white),
        ),
        home: const RemoteScreen(mode: RemoteMode.receiver),
      );
}
