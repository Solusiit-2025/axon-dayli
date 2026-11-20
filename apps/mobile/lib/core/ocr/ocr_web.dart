import 'dart:async';
import 'dart:js_interop';

import '../ocr_parser.dart';

@JS('performOcr')
external JSPromise<JSString> _performOcrJs(JSString imageSrc);

Future<OcrResult?> runOcr(String imageDataUrl) async {
  try {
    final jsPromise = _performOcrJs(imageDataUrl.toJS);
    final jsString = await jsPromise.toDart;
    final text = jsString.toDart;
    return OcrParser.parse(text);
  } catch (_) {
    return null;
  }
}
