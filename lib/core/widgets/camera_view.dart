import 'dart:io';
import 'dart:math' as math;

import 'package:ai_trainer/core/camera/camera_frame.dart';
import 'package:ai_trainer/core/theme/spotter_theme.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

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
  // false = the whole picture is shown with black bars (widest view, nothing cropped),
  // true = the picture fills the whole area (edges are cropped). The button in the top bar
  // switches. Starts on false so the camera sees as much of you as possible.
  bool _fill = false;

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
      // picture anyway, so a 720p stream only costs conversion time.
      final controller = CameraController(
        _camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      // widest view the camera offers (on phones whose camera can zoom out below 1x this
      // gives a wider field of view; on the rest it is 1x and changes nothing)
      try {
        final minZoom = await controller.getMinZoomLevel();
        await controller.setZoomLevel(minZoom);
      } catch (_) {}
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

  /// small dark button with a mint border, same look as the buttons on the right of the bar
  Widget _barButton(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: Material(
      color: Sp.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sp.rChip),
        side: const BorderSide(color: Sp.mint),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Sp.rChip),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(icon, size: 18, color: Sp.mint),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (!_ready || controller == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      // fit mode = the plain preview (whole picture, nothing cropped).
      // fill mode = scale the preview up until it covers the whole area (edges are cropped).
      body = LayoutBuilder(
        builder: (context, c) {
          // the skeleton layer repaints on its own: the camera preview is not rebuilt per frame
          final preview = CameraPreview(
            controller,
            child: RepaintBoundary(child: widget.overlay),
          );
          if (!_fill) return Center(child: preview);
          final o = controller.value.deviceOrientation;
          final landscape =
              o == DeviceOrientation.landscapeLeft ||
              o == DeviceOrientation.landscapeRight;
          final previewAspect = landscape
              ? controller.value.aspectRatio
              : 1 / controller.value.aspectRatio;
          final areaAspect = c.biggest.aspectRatio;
          final scale = math.max(
            areaAspect / previewAspect,
            previewAspect / areaAspect,
          );
          return ClipRect(
            child: Transform.scale(
              scale: scale,
              child: Center(child: preview),
            ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // the look is set here, so it does not depend on which theme is active
        backgroundColor: Sp.canvas,
        foregroundColor: Sp.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        automaticallyImplyLeading: false,
        // back button: maybePop goes through the screen's PopScope, so the workout screen
        // still asks "Leave the workout?" before closing
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: _barButton(
              Icons.arrow_back,
              'Back',
              () => Navigator.of(context).pop(),
            ),
          ),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Sp.headlineSm.copyWith(color: Sp.white),
        ),
        actions: [
          // too many buttons (e.g. curls: + the arm picker) covered the back button on a phone:
          // keep room for it; if they still do not fit they scroll, with the first one (the
          // voice coach) always in view
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width - 72,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...?widget.actions,
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 8),
                    // the icon shows what a tap will do (an icon only: the bar has to fit on a phone)
                    child: _barButton(
                      _fill ? Icons.fit_screen : Icons.fullscreen,
                      _fill ? 'Fit the camera' : 'Fill the screen',
                      () => setState(() => _fill = !_fill),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}
