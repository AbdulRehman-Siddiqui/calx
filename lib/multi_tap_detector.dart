import 'dart:async';

typedef VoidCallback = void Function();

/// Detects 1/2/3 taps in a short window.
/// This stays stable even if an iOS UiKitView exists in the widget tree.
class MultiTapDetector {
  MultiTapDetector({
    required this.onSingle,
    required this.onDouble,
    required this.onTriple,
    this.window = const Duration(milliseconds: 320),
  });

  final VoidCallback onSingle;
  final VoidCallback onDouble;
  final VoidCallback onTriple;
  final Duration window;

  int _count = 0;
  Timer? _timer;

  void registerTap() {
    _count++;
    _timer?.cancel();
    _timer = Timer(window, () {
      final c = _count;
      _count = 0;

      if (c == 1) onSingle();
      else if (c == 2) onDouble();
      else if (c >= 3) onTriple();
    });
  }

  void dispose() => _timer?.cancel();
}
