import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'cv.dart';
import 'spotter_theme.dart';

/// the "while True: cap.read() ... cv2.imshow()" loop.
/// Opens the camera (cv2.VideoCapture(0)), gives every frame to [onFrame]
/// and shows the camera with everything drawn on the frame.
class CameraView extends StatefulWidget {
  // CHANGED: optional [actions] (e.g. the arm selector of the biceps curl) shown in the app bar
  const CameraView({super.key, required this.title, required this.onFrame, this.actions});

  final String title;
  final Future<void> Function(Frame img) onFrame;
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
  // frames sent to the detector and not answered yet; 2 was tested and gave the
  // same fps (ML Kit works on one frame at a time) but the skeleton lagged more
  static const _maxInFlight = 1;
  int _inFlight = 0;
  int _sent = 0, _shown = 0;
  CameraImage? _pending;
  // the skeleton is repainted through this notifier: the camera preview itself is NOT
  // rebuilt for every frame any more (that was a full widget rebuild at every frame)
  final ValueNotifier<Frame?> _frame = ValueNotifier<Frame?>(null);
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
    // while the detector is full keep only the newest frame, and start it the
    // moment a slot is free instead of waiting for the camera's next frame
    if (_inFlight >= _maxInFlight) {
      _pending = image;
      return;
    }
    _run(image);
  }

  void _run(CameraImage image) {
    final input = _toInputImage(image);
    if (input == null) return;
    _inFlight++;
    final id = ++_sent;

    final meta = input.metadata!;
    // iOS: the camera plugin already turns the stream upright and mirrors the front camera
    // (camera_avfoundation: videoOrientation + isVideoMirrored), so the picture is used as it
    // is: no width/height swap and no second mirroring (same as the google_mlkit example's
    // coordinates_translator). Android is unchanged.
    final sideways = !Platform.isIOS &&
        (meta.rotation == InputImageRotation.rotation90deg ||
            meta.rotation == InputImageRotation.rotation270deg);
    final w = (sideways ? image.height : image.width).toDouble();
    final h = (sideways ? image.width : image.height).toDouble();
    final img = Frame(input, w, h,
        mirror: !Platform.isIOS && _camera.lensDirection == CameraLensDirection.front,
        detectScale: image.width / meta.size.width);

    widget.onFrame(img).then((_) {
      // ML Kit answers in order, but never show an older frame over a newer one
      if (mounted && id > _shown) {
        _shown = id;
        _frame.value = img; // repaints only the skeleton layer
      }
    }).catchError((Object e) {
      debugPrint('frame error: $e');
    }).whenComplete(() {
      _inFlight--;
      final next = _pending;
      _pending = null;
      if (next != null && mounted) _run(next);
    });
  }

  /// NV21 picture at half the width and height (every 2nd pixel), so less data
  /// has to be copied to ML Kit and converted. Same shape, so same angles.
  /// Only used for big pictures (wider than 800 px); the 640x480 stream goes as it is.
  static (Uint8List, int, int) _halfSize(Uint8List src, int width, int height, int stride) {
    final w2 = (width ~/ 2) & ~1, h2 = (height ~/ 2) & ~1;
    final out = Uint8List(w2 * h2 * 3 ~/ 2);
    // Y plane
    var o = 0;
    for (var y = 0; y < h2; y++) {
      var s = 2 * y * stride;
      for (var x = 0; x < w2; x++, s += 2) {
        out[o++] = src[s];
      }
    }
    // interleaved V/U plane (one V,U pair for every 2x2 pixels)
    final vu = stride * height;
    for (var y = 0; y < h2 ~/ 2; y++) {
      var s = vu + 2 * y * stride;
      for (var x = 0; x < w2 ~/ 2; x++, s += 4) {
        out[o++] = src[s];
        out[o++] = src[s + 1];
      }
    }
    return (out, w2, h2);
  }

  InputImage? _toInputImage(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;
    final sensor = _camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensor);
    } else {
      var comp = _orientations[controller.value.deviceOrientation];
      if (comp == null) return null;
      comp = _camera.lensDirection == CameraLensDirection.front
          ? (sensor + comp) % 360
          : (sensor - comp + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(comp);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    var bytes = plane.bytes;
    var width = image.width, height = image.height, bytesPerRow = plane.bytesPerRow;
    // only when the buffer really is a full NV21 picture (Y rows + V/U rows) and big enough
    // to be worth shrinking
    if (Platform.isAndroid &&
        width > 800 &&
        bytes.length >= bytesPerRow * (height + height ~/ 2 - 1) + width) {
      (bytes, width, height) = _halfSize(bytes, width, height, bytesPerRow);
      bytesPerRow = width;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      ),
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
    _frame.dispose();
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
        final preview = CameraPreview(
          controller,
          child: RepaintBoundary(child: CustomPaint(painter: FramePainter(_frame))),
        );
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