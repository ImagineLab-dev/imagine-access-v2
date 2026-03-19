import 'dart:typed_data';

/// Stub for non-web platforms — download is handled via share_plus
void downloadPdfWeb(Uint8List bytes, String fileName) {
  throw UnsupportedError('downloadPdfWeb is only supported on web');
}
