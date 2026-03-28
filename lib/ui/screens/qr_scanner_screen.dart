import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR code scanner.
///
/// Returns the scanned raw string via [Navigator.pop] when a QR code is
/// detected, or `null` if the user presses back.
///
/// Only fully functional on Android, iOS, macOS, and Web.  On other platforms
/// (e.g. Windows) a friendly "not available" message is shown instead.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, this.title = 'Ler QR Code'});

  final String title;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _controller;
  bool _detected = false;

  static bool get _platformSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (_platformSupported) {
      _controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
      );
    }
  }

  @override
  void dispose() {
    if (_platformSupported) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_platformSupported) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Scanner de QR Code não disponível nesta plataforma.\n\n'
              'Use um dispositivo Android ou iOS.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_detected) return;
              final raw =
                  capture.barcodes
                      .where((b) => b.rawValue != null)
                      .firstOrNull
                      ?.rawValue;
              if (raw != null) {
                _detected = true;
                Navigator.of(context).pop(raw);
              }
            },
          ),

          // Scan-area overlay hint
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Aponte para um QR Code MeshCore',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
