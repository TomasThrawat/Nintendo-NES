import 'package:shared_preferences/shared_preferences.dart';

import '../core/controller/nes_controller.dart';

class ControlPlacement {
  const ControlPlacement({
    required this.x,
    required this.y,
    this.scale = 1,
    this.visible = true,
  });

  final double x;
  final double y;
  final double scale;
  final bool visible;

  ControlPlacement copyWith({
    double? x,
    double? y,
    double? scale,
    bool? visible,
  }) =>
      ControlPlacement(
        x: (x ?? this.x).clamp(0.04, 0.96).toDouble(),
        y: (y ?? this.y).clamp(0.12, 0.94).toDouble(),
        scale: (scale ?? this.scale).clamp(0.60, 1.60).toDouble(),
        visible: visible ?? this.visible,
      );
}

/// Saved individually per NES button, matching WiFiPad's move/size/show editor.
class ControlLayoutStore {
  ControlLayoutStore._();

  static const String _prefix = 'nes_control_';

  static const Map<NesButton, ControlPlacement> defaults =
      <NesButton, ControlPlacement>{
    NesButton.up: ControlPlacement(x: 0.15, y: 0.43),
    NesButton.down: ControlPlacement(x: 0.15, y: 0.70),
    NesButton.left: ControlPlacement(x: 0.075, y: 0.565),
    NesButton.right: ControlPlacement(x: 0.225, y: 0.565),
    NesButton.b: ControlPlacement(x: 0.74, y: 0.69),
    NesButton.a: ControlPlacement(x: 0.86, y: 0.57),
    NesButton.select: ControlPlacement(x: 0.43, y: 0.84),
    NesButton.start: ControlPlacement(x: 0.57, y: 0.84),
  };

  static Future<Map<NesButton, ControlPlacement>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return <NesButton, ControlPlacement>{
      for (final button in NesButton.values)
        button: ControlPlacement(
          x: prefs.getDouble(_key(button, 'x')) ?? defaults[button]!.x,
          y: prefs.getDouble(_key(button, 'y')) ?? defaults[button]!.y,
          scale: prefs.getDouble(_key(button, 'scale')) ?? 1,
          visible: prefs.getBool(_key(button, 'visible')) ?? true,
        ).copyWith(),
    };
  }

  static Future<void> save(
    NesButton button,
    ControlPlacement placement,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final safe = placement.copyWith();
    await prefs.setDouble(_key(button, 'x'), safe.x);
    await prefs.setDouble(_key(button, 'y'), safe.y);
    await prefs.setDouble(_key(button, 'scale'), safe.scale);
    await prefs.setBool(_key(button, 'visible'), safe.visible);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    for (final button in NesButton.values) {
      for (final field in const <String>['x', 'y', 'scale', 'visible']) {
        await prefs.remove(_key(button, field));
      }
    }
  }

  static String _key(NesButton button, String field) =>
      _prefix + button.name + '_' + field;
}
