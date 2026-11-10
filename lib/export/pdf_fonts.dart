/// Loads the bundled Noto Sans fonts for PDF export (umlauts, en dash, …).
library;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:pdf/widgets.dart' as pw;

const kPdfFontRegular = 'assets/fonts/NotoSans-Regular.ttf';
const kPdfFontBold = 'assets/fonts/NotoSans-Bold.ttf';

class PdfFonts {
  const PdfFonts(this.regular, this.bold);
  final pw.Font regular;
  final pw.Font bold;
}

/// The bundled fonts, or null if they can't be loaded (the PDF then falls
/// back to the built-in Helvetica with Latin-1-safe text).
Future<PdfFonts?> loadPdfFonts([AssetBundle? bundle]) async {
  final b = bundle ?? rootBundle;
  try {
    final regular = await b.load(kPdfFontRegular);
    final bold = await b.load(kPdfFontBold);
    return PdfFonts(pw.Font.ttf(regular), pw.Font.ttf(bold));
  } catch (_) {
    return null;
  }
}
