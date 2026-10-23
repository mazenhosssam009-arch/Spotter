import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/core/theme/spotter_theme.dart';

/// the "while True: cap.read() ... cv2.imshow()" loop.
/// Opens the camera (cv2.VideoCapture(0)), gives every frame to [onFrame]
/// and shows the camera with [overlay] (what was drawn on the frame) on top.
/// The bloc that gets the frames decides which ones go to the detector.
class CameraView extends StatefulWidget {
  const CameraView({
    super.key,
    required this.title,
    required this.onFrame,
    required this.overlay,
    this.actions,
  });

  final String title;
  final void Function(CameraFrame frame) onFrame;
  final Widget overlay;
  // e.g. the arm selector of the biceps curl, shown in the app bar
  final List<Widget>? actions;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _controller;
  late CameraDescription _camera;
  bool _ready = false;
  String? _error;
  // true = the picture fills the whole area (edges are cropped), false = the whole
  // picture is shown with black bars. The button in the top bar switches.
  bool _fill = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found');
        return;
      }
      // the selfie camera, like a laptop webcam
      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      // MEDIUM (about 640x480) is what makes the app fast: the pose model looks at a small
      // picture anyway, so a 720p stream only costs conversion time. The picture is shown
      // full-screen (see _fill), so it still looks big.
      final controller = CameraController(
        _camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      await controller.startImageStream(_process);
      setState(() => _ready = true);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    }
  }

  void _process(CameraImage image) {
    if (!mounted) return;
    final frame = _toCameraFrame(image);
    if (frame != null) widget.onFrame(frame);
  }

  CameraFrame? _toCameraFrame(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;
    final sensor = _camera.sensorOrientation;
    int rotation;
    if (Platform.isIOS) {
      rotation = sensor;
    } else {
      final comp = _orientations[controller.value.deviceOrientation];
      if (comp == null) return null;
      rotation = _camera.lensDirection == CameraLensDirection.front
          ? (sensor + comp) % 360
          : (sensor - comp + 360) % 360;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return CameraFrame(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      rotationDegrees: rotation,
      format: image.format.raw as int,
      isFrontCamera: _camera.lensDirection == CameraLensDirection.front,
      // iOS: upright and (front camera) mirrored already, see CameraFrame.isUprightStream
      isUprightStream: Platform.isIOS,
      capturedAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        controller.stopImageStream().whenComplete(controller.dispose);
      } else {
        controller.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
        ),
      );
    } else if (!_ready || controller == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      // standard camera-plugin way to fill the screen: scale the preview up until it covers
      // the whole area (the edges that do not fit are cropped). Fit mode = the plain preview.
      body = LayoutBuilder(builder: (context, c) {
        // the skeleton layer repaints on its own: the camera preview is not rebuilt per frame
        final preview = CameraPreview(controller, child: RepaintBoundary(child: widget.overlay));
        if (!_fill) return Center(child: preview);
        var scale = c.biggest.aspectRatio * controller.value.aspectRatio;
        if (scale < 1) scale = 1 / scale;
        return ClipRect(
          child: Transform.scale(scale: scale, child: Center(child: preview)),
        );
      });
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          ...?widget.actions,
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 8),
            child: Material(
              color: Sp.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Sp.rChip), side: const BorderSide(color: Sp.mint)),
              child: InkWell(
                borderRadius: BorderRadius.circular(Sp.rChip),
                onTap: () => setState(() => _fill = !_fill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_fill ? Icons.fit_screen : Icons.fullscreen, size: 18, color: Sp.mint),
                    const SizedBox(width: 6),
                    // shows what a tap will do
                    Text(_fill ? 'FIT' : 'FILL', style: Sp.labelMd.copyWith(color: Sp.mint)),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}
