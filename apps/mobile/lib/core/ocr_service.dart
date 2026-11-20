import 'ocr/ocr_stub.dart'
    if (dart.library.js_interop) 'ocr/ocr_web.dart'
    if (dart.library.io) 'ocr/ocr_native.dart';
import 'ocr_parser.dart';

class OcrService {
  static Future<OcrResult?> scanReceipt(String imageDataUrl) async {
    return runOcr(imageDataUrl);
  }
}
