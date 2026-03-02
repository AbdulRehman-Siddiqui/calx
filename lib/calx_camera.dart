import 'package:flutter/services.dart';

/// Wrapper around the iOS MethodChannel implemented in Swift.
class CalxCamera {
  CalxCamera._();
  static final CalxCamera instance = CalxCamera._();

  static const MethodChannel _ch = MethodChannel('calx/camera');

  Future<void> init() async {
    await _ch.invokeMethod('init');
  }

  Future<String> startRecording() async {
    final res = await _ch.invokeMethod<dynamic>('startRecording');
    return res?.toString() ?? 'OK';
  }

  Future<void> stopRecording() async {
    await _ch.invokeMethod('stopRecording');
  }

  Future<void> setZoom(double zoom) async {
    await _ch.invokeMethod('setZoom', {'zoom': zoom});
  }

  Future<void> setFps(int fps) async {
    await _ch.invokeMethod('setFps', {'fps': fps});
  }
}
