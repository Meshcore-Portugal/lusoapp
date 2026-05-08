part of '../channels_list_screen.dart';

// Channel QR code dialog with QR image share + plain text share
// ---------------------------------------------------------------------------

class _ChannelQrDialog extends StatefulWidget {
  const _ChannelQrDialog({required this.uri, required this.displayName});

  final String uri;
  final String displayName;

  @override
  State<_ChannelQrDialog> createState() => _ChannelQrDialogState();
}

class _ChannelQrDialogState extends State<_ChannelQrDialog> {
  final _qrKey = GlobalKey();
  bool _sharing = false;
  bool _sharingText = false;

  Future<void> _shareQr() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      final xFile = XFile.fromData(
        pngBytes,
        name: '${widget.displayName}.png',
        mimeType: 'image/png',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: widget.uri,
          subject: 'Canal MeshCore: ${widget.displayName}',
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareText() async {
    setState(() => _sharingText = true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: widget.uri,
          subject: 'Canal MeshCore: ${widget.displayName}',
        ),
      );
    } finally {
      if (mounted) setState(() => _sharingText = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(context.l10n.channelsQRTitle),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              key: _qrKey,
              child: QrImageView(
                data: widget.uri,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Partilhe este QR Code para dar acesso ao canal',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonClose),
        ),
        TextButton.icon(
          onPressed: _sharingText ? null : _shareText,
          icon:
              _sharingText
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.text_fields),
          label: Text(context.l10n.channelsShareText),
        ),
        FilledButton.icon(
          onPressed: _sharing ? null : _shareQr,
          icon:
              _sharing
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.share),
          label: Text(context.l10n.channelsShareQR),
        ),
      ],
    );
  }
}
