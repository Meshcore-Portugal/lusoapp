import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR code scanner.
///
/// Returns the scanned raw string via [Navigator.pop] when a QR code is
/// detected, or `null` if the user presses back.
///
/// On platforms without camera support (Windows/Linux) only the
/// gallery/file-upload path is available.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, this.title = 'Ler QR Code'});

  final String title;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _controller;
  bool _detected = false;
  bool _analyzing = false;

  /// Platforms where the live camera scanner is available.
  static bool get _cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Platforms where image_picker gallery / file-upload works.
  static bool get _gallerySupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (_cameraSupported) {
      _controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
      );
    }
  }

  @override
  void dispose() {
    if (_cameraSupported) _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    setState(() => _analyzing = true);
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;

      final capture = await _controller.analyzeImage(image.path);
      if (!mounted) return;

      final raw =
          capture?.barcodes
              .where((b) => b.rawValue != null)
              .firstOrNull
              ?.rawValue;

      if (raw != null) {
        _detected = true;
        Navigator.of(context).pop(raw);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhum QR Code encontrado na imagem.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const galleryTooltip = kIsWeb ? 'Carregar imagem QR' : 'Abrir da galeria';

    // Platforms with no camera — show just the gallery/upload option.
    if (!_cameraSupported) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code_scanner, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Câmara não disponível nesta plataforma.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_gallerySupported)
                  FilledButton.icon(
                    onPressed: _analyzing ? null : _pickFromGallery,
                    icon:
                        _analyzing
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.photo_library_outlined),
                    label: const Text('Abrir imagem'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_gallerySupported)
            _analyzing
                ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
                : IconButton(
                  tooltip: galleryTooltip,
                  icon: const Icon(Icons.photo_library_outlined),
                  onPressed: _pickFromGallery,
                ),
        ],
      ),
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
