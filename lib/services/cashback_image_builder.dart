import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

/// Returns the advance pixel width of [text] in [font].
int _textWidth(img.BitmapFont font, String text) {
  int w = 0;
  for (final cp in text.runes) {
    final g = font.characters[cp];
    if (g != null) w += g.xAdvance;
  }
  return w;
}

/// X position that centres [text] within an area starting at [areaLeft]
/// with width [areaWidth].
int _centreX(img.BitmapFont font, String text, int areaLeft, int areaWidth) {
  final tw = _textWidth(font, text);
  return areaLeft + ((areaWidth - tw) ~/ 2).clamp(0, areaWidth);
}

/// Renders the full cashback reward block as a single bordered bitmap:
///   • "Expires in 12 hours" header (centred, bold via larger font)
///   • Left: "You've earned / Points & / X% Cashback / Scan to claim" (centred)
///   • Right: QR code
/// Returned as PNG bytes for use with [RcImage].
Uint8List buildCashbackImage(String url, int cashbackPercent) {
  const printWidth = 384; // 58 mm @ 203 dpi
  const outerPad = 6;    // gap between paper edge and box
  const borderW = 2;     // box border thickness
  const innerPadH = 10;  // horizontal padding inside box
  const innerPadV = 10;  // vertical padding inside box
  const headerFontH = 14;
  const headerGap = 10;  // space below header before content
  const lineSpacing = 6;
  const smallFontH = 14;
  const largeFontH = 24;
  const textQrGap = 8;   // gap between text column and QR

  // ── QR matrix ─────────────────────────────────────────────────────────────
  final qrCode = QrCode.fromData(
    data: url,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qrImage = QrImage(qrCode);
  final moduleCount = qrImage.moduleCount;

  // Box inner width (between the two border lines)
  final boxInnerW = printWidth - 2 * outerPad - 2 * borderW;

  // Size QR to fit the right ~44 % of the box interior
  final qrAreaW = (boxInnerW * 0.44).round();
  final moduleSize = (qrAreaW / moduleCount).floor().clamp(3, 8);
  final qrPx = moduleCount * moduleSize;

  // Text column width (remaining interior width after QR + gap + inner pads)
  final textAreaW = boxInnerW - 2 * innerPadH - qrPx - textQrGap;

  // Text block height
  const textBlockH = smallFontH + lineSpacing +
      largeFontH + lineSpacing +
      largeFontH + lineSpacing +
      smallFontH; // = 94

  final contentH = textBlockH > qrPx ? textBlockH : qrPx;

  // ── Canvas ─────────────────────────────────────────────────────────────────
  final imageH = borderW * 2 +
      innerPadV +
      headerFontH +
      headerGap +
      contentH +
      innerPadV;

  final image = img.Image(width: printWidth, height: imageH);
  img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));

  final black = img.ColorRgba8(0, 0, 0, 255);

  // ── Box border ─────────────────────────────────────────────────────────────
  img.drawRect(
    image,
    x1: outerPad,
    y1: 0,
    x2: printWidth - outerPad - 1,
    y2: imageH - 1,
    color: black,
    thickness: borderW,
  );

  // ── "Expires in 12 hours" — centred in the box header ─────────────────────
  const headerText = 'Expires in 12 hours';
  final headerX = _centreX(
    img.arial14,
    headerText,
    outerPad + borderW + innerPadH,
    boxInnerW - 2 * innerPadH,
  );
  img.drawString(
    image,
    headerText,
    font: img.arial14,
    x: headerX,
    y: borderW + innerPadV,
    color: black,
  );

  // ── Content area Y start ───────────────────────────────────────────────────
  final contentTop = borderW + innerPadV + headerFontH + headerGap;

  // ── QR on the right (vertically centred in content area) ──────────────────
  final qrLeft = printWidth - outerPad - borderW - innerPadH - qrPx;
  final qrTop = contentTop + ((contentH - qrPx) ~/ 2).clamp(0, contentH);

  for (int row = 0; row < moduleCount; row++) {
    for (int col = 0; col < moduleCount; col++) {
      if (qrImage.isDark(row, col)) {
        for (int dy = 0; dy < moduleSize; dy++) {
          for (int dx = 0; dx < moduleSize; dx++) {
            image.setPixel(
              qrLeft + col * moduleSize + dx,
              qrTop + row * moduleSize + dy,
              black,
            );
          }
        }
      }
    }
  }

  // ── Text on the left (each line centred, block vertically centred) ─────────
  final textLeft = outerPad + borderW + innerPadH;
  int textY = contentTop + ((contentH - textBlockH) ~/ 2).clamp(0, contentH);

  void drawCentred(String text, img.BitmapFont font) {
    final x = _centreX(font, text, textLeft, textAreaW);
    img.drawString(image, text, font: font, x: x, y: textY, color: black);
  }

  drawCentred("You've earned", img.arial14);
  textY += smallFontH + lineSpacing;

  drawCentred('Points &', img.arial24);
  textY += largeFontH + lineSpacing;

  drawCentred('$cashbackPercent% Cashback', img.arial24);
  textY += largeFontH + lineSpacing;

  drawCentred('Scan to claim', img.arial14);

  return Uint8List.fromList(img.encodePng(image));
}
