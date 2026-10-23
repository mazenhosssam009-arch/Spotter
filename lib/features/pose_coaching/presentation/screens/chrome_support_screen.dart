import 'package:flutter/material.dart';

class ChromeSupportScreen extends StatelessWidget {
  const ChromeSupportScreen({super.key, required this.feature});

  final String feature;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chrome support')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone_android, size: 48),
                const SizedBox(height: 16),
                Text(
                  '$feature is not available in Chrome',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This feature uses Google ML Kit and live camera image '
                  'streaming, which are not supported by this Flutter web '
                  'build. Run Spotter on an Android or iOS device to use '
                  'camera-based detection.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to menu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
