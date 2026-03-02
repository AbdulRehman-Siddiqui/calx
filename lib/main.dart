import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'calx_camera.dart';
import 'multi_tap_detector.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CalxApp());
}

class CalxApp extends StatelessWidget {
  const CalxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'calx',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const CalxHome(),
    );
  }
}

class CalxHome extends StatefulWidget {
  const CalxHome({super.key});

  @override
  State<CalxHome> createState() => _CalxHomeState();
}

class _CalxHomeState extends State<CalxHome> {
  bool _isRecording = false;

  bool _showPreview = false;
  bool _showUtility = false;

  bool _showRecText = true;

  double _zoom = 1.0;
  int _fps = 30;

  late final MultiTapDetector _tapDetector;

  @override
  void initState() {
    super.initState();
    _tapDetector = MultiTapDetector(
      onSingle: _toggleRecording,
      onDouble: _backToOledBlack,
      onTriple: _toggleUtility,
    );

    _initNative();
  }

  Future<void> _initNative() async {
    try {
      await CalxCamera.instance.init();
    } catch (e) {
      debugPrint('[calx] init error: $e');
      setState(() => _showUtility = true);
    }
  }

  @override
  void dispose() {
    _tapDetector.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        await CalxCamera.instance.stopRecording();
        setState(() => _isRecording = false);
      } else {
        await CalxCamera.instance.startRecording();
        setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint('[calx] toggleRecording error: $e');
      setState(() => _showUtility = true);
    }
  }

  void _backToOledBlack() {
    setState(() {
      _showPreview = false;
      _showUtility = false;
    });
  }

  void _toggleUtility() => setState(() => _showUtility = !_showUtility);

  Future<void> _applyZoom(double z) async {
    setState(() => _zoom = z);
    try {
      await CalxCamera.instance.setZoom(z);
    } catch (e) {
      debugPrint('[calx] setZoom error: $e');
    }
  }

  Future<void> _applyFps(int fps) async {
    setState(() => _fps = fps);
    try {
      await CalxCamera.instance.setFps(fps);
    } catch (e) {
      debugPrint('[calx] setFps error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // OLED black
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _AlwaysMountedPreview(visible: _showPreview),

            Positioned.fill(
              child: _GestureSurface(
                onTap: _tapDetector.registerTap,
                onLongPressStart: () => setState(() => _showPreview = true),
                onLongPressEnd: () => setState(() => _showPreview = false),
              ),
            ),

            if (_isRecording && !_showPreview && !_showUtility)
              Positioned(
                top: 10,
                left: 10,
                child: _RecIndicator(showText: _showRecText),
              ),

            if (_showPreview)
              _ControlsOverlay(
                zoom: _zoom,
                fps: _fps,
                onZoom: _applyZoom,
                onFps: _applyFps,
                onClose: () => setState(() => _showPreview = false),
              ),

            if (_showUtility)
              _UtilityOverlay(
                isRecording: _isRecording,
                zoom: _zoom,
                fps: _fps,
                showRecText: _showRecText,
                onToggleRecText: () => setState(() => _showRecText = !_showRecText),
                onClose: () => setState(() => _showUtility = false),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlwaysMountedPreview extends StatelessWidget {
  const _AlwaysMountedPreview({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    // Keep it mounted. IgnorePointer ensures Flutter receives gestures.
    return IgnorePointer(
      ignoring: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: visible ? 1.0 : 0.0,
        child: const ColoredBox(
          color: Colors.black,
          child: _CalxUiKitPreview(),
        ),
      ),
    );
  }
}

class _CalxUiKitPreview extends StatelessWidget {
  const _CalxUiKitPreview();

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const Center(
        child: Text('iOS preview only', style: TextStyle(color: Colors.white54)),
      );
    }

    // Eager recognizer included; IgnorePointer above keeps gestures reliable.
    final recognizers = <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    };

    return UiKitView(
      viewType: 'calx/camera_preview',
      gestureRecognizers: recognizers,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

class _GestureSurface extends StatelessWidget {
  const _GestureSurface({
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      child: const SizedBox.expand(),
    );
  }
}

class _RecIndicator extends StatelessWidget {
  const _RecIndicator({required this.showText});
  final bool showText;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
        ),
        if (showText) ...[
          const SizedBox(width: 6),
          const Text(
            'REC',
            style: TextStyle(
              fontSize: 10,
              height: 1,
              color: Colors.red,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ],
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({
    required this.zoom,
    required this.fps,
    required this.onZoom,
    required this.onFps,
    required this.onClose,
  });

  final double zoom;
  final int fps;
  final ValueChanged<double> onZoom;
  final ValueChanged<int> onFps;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Container(color: Colors.black.withOpacity(0.15)),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.70),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('Preview Controls', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close, size: 18),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 52, child: Text('Zoom', style: TextStyle(fontSize: 12))),
                      Expanded(
                        child: Slider(
                          value: zoom,
                          min: 0.5,
                          max: 6.0,
                          divisions: 55,
                          label: zoom.toStringAsFixed(2),
                          onChanged: onZoom,
                        ),
                      ),
                      SizedBox(width: 44, child: Text('${zoom.toStringAsFixed(1)}x', textAlign: TextAlign.right)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const SizedBox(width: 52, child: Text('FPS', style: TextStyle(fontSize: 12))),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: fps,
                        items: const [
                          DropdownMenuItem(value: 24, child: Text('24')),
                          DropdownMenuItem(value: 30, child: Text('30')),
                          DropdownMenuItem(value: 60, child: Text('60')),
                        ],
                        onChanged: (v) {
                          if (v != null) onFps(v);
                        },
                      ),
                      const Spacer(),
                      const Text('Hold = show\nRelease = hide', style: TextStyle(fontSize: 10, color: Colors.white54)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UtilityOverlay extends StatelessWidget {
  const _UtilityOverlay({
    required this.isRecording,
    required this.zoom,
    required this.fps,
    required this.showRecText,
    required this.onToggleRecText,
    required this.onClose,
  });

  final bool isRecording;
  final double zoom;
  final int fps;
  final bool showRecText;
  final VoidCallback onToggleRecText;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.82),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Utility', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 12),
                _kv('Recording', isRecording ? 'ON' : 'OFF'),
                _kv('Zoom', '${zoom.toStringAsFixed(2)}x'),
                _kv('FPS', '$fps'),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: showRecText,
                  onChanged: (_) => onToggleRecText(),
                  title: const Text('Show tiny "REC" text'),
                  subtitle: const Text('If the dot alone is too subtle'),
                ),
                const SizedBox(height: 18),
                const Text('Gestures', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('• Single tap: start/stop recording'),
                const Text('• Double tap: return to OLED black'),
                const Text('• Long press: preview + controls (hold)'),
                const Text('• Triple tap: utility view'),
                const Spacer(),
                const Text(
                  'Preview view stays mounted to avoid re-init glitches.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(k, style: const TextStyle(color: Colors.white70))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
