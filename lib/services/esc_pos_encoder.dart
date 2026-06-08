import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'receipt_commands.dart';

class EscPosEncoder {
  const EscPosEncoder({this.lineWidth = 32});

  // 32 chars = 58 mm paper (standard for BT receipt printers).
  // Change to 42 for 80 mm paper.
  final int lineWidth;

  // Dot width of the printable area.
  // 58 mm @ 203 dpi ≈ 384 dots; 80 mm @ 203 dpi ≈ 576 dots.
  int get _printDots => lineWidth <= 32 ? 384 : 576;

  // ── ESC/POS command constants ──────────────────────────────────────────────

  static const _init = [0x1B, 0x40]; // ESC @ — initialize
  static const _lf = [0x0A]; // line feed
  static const _boldOn = [0x1B, 0x45, 0x01]; // ESC E 1
  static const _boldOff = [0x1B, 0x45, 0x00]; // ESC E 0
  static const _fontBOn = [0x1B, 0x4D, 0x01]; // ESC M 1 — condensed font
  static const _fontBOff = [0x1B, 0x4D, 0x00]; // ESC M 0 — normal font
  static const _dblSizeOn = [0x1D, 0x21, 0x11]; // GS ! — double H+W
  static const _dblSizeOff = [0x1D, 0x21, 0x00];
  static const _alignLeft = [0x1B, 0x61, 0x00]; // ESC a 0
  static const _alignCenter = [0x1B, 0x61, 0x01]; // ESC a 1
  static const _alignRight = [0x1B, 0x61, 0x02]; // ESC a 2
  // GS V B n — partial cut with n-dot feed before cut
  static const _cut = [0x1D, 0x56, 0x42, 0x05];

  // ── Public ────────────────────────────────────────────────────────────────

  Uint8List encode(List<ReceiptCmd> commands) {
    final buf = <int>[];
    buf.addAll(_init);
    for (final cmd in commands) {
      switch (cmd) {
        case RcText():
          _writeText(buf, cmd);
        case RcRow():
          _writeRow(buf, cmd);
        case RcRow3():
          _writeRow3(buf, cmd);
        case RcItemRow():
          _writeItemRow(buf, cmd);
        case RcImage():
          _writeImage(buf, cmd);
        case RcQrCode():
          _writeQrCode(buf, cmd);
        case RcDivider():
          _writeDivider(buf, dashed: cmd.dashed);
        case RcFeed():
          _writeFeed(buf, cmd.lines);
        case RcCut():
          buf.addAll(_cut);
      }
    }
    return Uint8List.fromList(buf);
  }

  // ── Text ──────────────────────────────────────────────────────────────────

  void _writeText(List<int> buf, RcText cmd) {
    buf.addAll(_alignBytes(cmd.align));
    if (cmd.large) buf.addAll(_dblSizeOn);
    if (cmd.bold) buf.addAll(_boldOn);
    if (cmd.small) buf.addAll(_fontBOn);

    buf.addAll(_encode(cmd.text));
    buf.addAll(_lf);

    if (cmd.small) buf.addAll(_fontBOff);
    if (cmd.bold) buf.addAll(_boldOff);
    if (cmd.large) buf.addAll(_dblSizeOff);
    buf.addAll(_alignLeft);
  }

  // ── Row ───────────────────────────────────────────────────────────────────

  void _writeRow(List<int> buf, RcRow cmd) {
    buf.addAll(_alignLeft);
    if (cmd.bold) buf.addAll(_boldOn);

    final rightWidth = (lineWidth * 0.35).round();
    final leftWidth = lineWidth - rightWidth;

    // Amount column: never split. Truncate only if somehow wider than its column
    // (in practice RM prices always fit in ~11 chars).
    final right = cmd.right.length <= rightWidth
        ? cmd.right
        : cmd.right.substring(0, rightWidth);

    // Word-wrap the label into lines that each fit within leftWidth.
    final chunks = _wordWrap(cmd.left, leftWidth);

    for (int i = 0; i < chunks.length; i++) {
      final isLast = i == chunks.length - 1;
      if (isLast) {
        final label = cmd.rightAlignLabel
            ? chunks[i].padLeft(leftWidth)
            : chunks[i].padRight(leftWidth);
        final line = label + right.padLeft(rightWidth);
        buf.addAll(_encode(line));
      } else {
        final chunk = cmd.rightAlignLabel
            ? chunks[i].padLeft(leftWidth)
            : chunks[i];
        buf.addAll(_encode(chunk));
      }
      buf.addAll(_lf);
    }

    if (cmd.bold) buf.addAll(_boldOff);
  }

  // ── 3-column row (name | qty | price) ────────────────────────────────────

  void _writeRow3(List<int> buf, RcRow3 cmd) {
    buf.addAll(_alignLeft);
    if (cmd.bold) buf.addAll(_boldOn);

    final priceWidth = (lineWidth * 0.32).round();
    final qtyWidth = 4;
    final nameWidth = lineWidth - priceWidth - qtyWidth;

    final price = cmd.right.length <= priceWidth
        ? cmd.right
        : cmd.right.substring(0, priceWidth);
    final qty = cmd.middle.length <= qtyWidth
        ? cmd.middle
        : cmd.middle.substring(0, qtyWidth);

    final chunks = _wordWrap(cmd.left, nameWidth);

    for (int i = 0; i < chunks.length; i++) {
      final isLast = i == chunks.length - 1;
      if (isLast) {
        final line =
            chunks[i].padRight(nameWidth) + qty.padLeft(qtyWidth) + price.padLeft(priceWidth);
        buf.addAll(_encode(line));
      } else {
        buf.addAll(_encode(chunks[i]));
      }
      buf.addAll(_lf);
    }

    if (cmd.bold) buf.addAll(_boldOff);
  }

  // ── 5-column item row (name | price | qty | discount | amount) ───────────

  void _writeItemRow(List<int> buf, RcItemRow cmd) {
    buf.addAll(_alignLeft);
    if (cmd.isHeader) buf.addAll(_boldOn);

    final amtWidth = (lineWidth * 0.25).round();
    final discWidth = (lineWidth * 0.16).round();
    const qtyWidth = 3;
    final priceWidth = (lineWidth * 0.19).round();
    const priceQtySpacer = 1;
    final nameWidth = lineWidth - amtWidth - discWidth - qtyWidth - priceWidth - priceQtySpacer;

    final amount = cmd.amount.length <= amtWidth
        ? cmd.amount
        : cmd.amount.substring(0, amtWidth);
    final disc = cmd.discount.length <= discWidth
        ? cmd.discount
        : cmd.discount.substring(0, discWidth);
    final qty = cmd.qty.length <= qtyWidth
        ? cmd.qty
        : cmd.qty.substring(0, qtyWidth);
    final price = cmd.price.length <= priceWidth
        ? cmd.price
        : cmd.price.substring(0, priceWidth);

    final chunks = _wordWrap(cmd.name, nameWidth);
    for (int i = 0; i < chunks.length; i++) {
      final isLast = i == chunks.length - 1;
      if (isLast) {
        final line = '${chunks[i].padRight(nameWidth)}${price.padLeft(priceWidth)} ${qty.padLeft(qtyWidth)}${disc.padLeft(discWidth)}${amount.padLeft(amtWidth)}';
        buf.addAll(_encode(line));
      } else {
        buf.addAll(_encode(chunks[i]));
      }
      buf.addAll(_lf);
    }

    if (cmd.isHeader) buf.addAll(_boldOff);
  }

  // Word-wrap [text] so every chunk fits within [maxWidth] characters.
  // Breaks at the last space within the width; hard-breaks if no space exists.
  List<String> _wordWrap(String text, int maxWidth) {
    final input = text.trim();
    if (input.length <= maxWidth) return [input];

    final chunks = <String>[];
    var remaining = input;

    while (remaining.length > maxWidth) {
      // Find the last space that still fits within maxWidth.
      final breakAt = remaining.lastIndexOf(' ', maxWidth - 1);
      if (breakAt <= 0) {
        // No space found — hard-break at exactly maxWidth.
        chunks.add(remaining.substring(0, maxWidth));
        remaining = remaining.substring(maxWidth).trimLeft();
      } else {
        chunks.add(remaining.substring(0, breakAt));
        remaining = remaining.substring(breakAt + 1); // skip the space
      }
    }

    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }

  // ── Image (GS v 0 — raster bitmap) ───────────────────────────────────────
  //
  // Decodes the PNG/JPEG, scales it to fit the printable dot width, converts
  // to 1-bit monochrome (luminance threshold at 128), then emits the
  // GS v 0 raster-bitmap command supported by all ESC/POS printers.

  void _writeImage(List<int> buf, RcImage cmd) {
    final decoded = img.decodeImage(cmd.bytes);
    if (decoded == null) return;

    final targetW = _printDots;
    final targetH = (decoded.height * targetW / decoded.width).round();

    final resized = img.copyResize(
      decoded,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.linear,
    );

    final bytesPerRow = (targetW + 7) ~/ 8;

    buf.addAll(_alignBytes(cmd.align));

    // GS v 0 m xL xH yL yH  (m=0: normal scale)
    buf.addAll([
      0x1D, 0x76, 0x30, 0x00,
      bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF,
      targetH & 0xFF, (targetH >> 8) & 0xFF,
    ]);

    for (int y = 0; y < targetH; y++) {
      for (int bx = 0; bx < bytesPerRow; bx++) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final x = bx * 8 + bit;
          if (x < targetW) {
            final pixel = resized.getPixel(x, y);
            // Composite against white background so transparent areas print white.
            final a = pixel.a / 255.0;
            final r = (pixel.r * a + 255 * (1 - a));
            final g = (pixel.g * a + 255 * (1 - a));
            final b = (pixel.b * a + 255 * (1 - a));
            final luma = (0.299 * r + 0.587 * g + 0.114 * b).round();
            // Dark pixel (luma < 128) → bit 1; light → bit 0.
            if (luma < 128) byte |= (0x80 >> bit);
          }
        }
        buf.add(byte);
      }
    }

    buf.addAll(_alignLeft);
    buf.addAll(_lf);
  }

  // ── QR code (GS ( k) ──────────────────────────────────────────────────────

  void _writeQrCode(List<int> buf, RcQrCode cmd) {
    final data = _encode(cmd.data);
    final dataLen = data.length + 3; // +3 for cn, fn, m bytes in store cmd

    buf.addAll(_alignCenter);

    // 1. Select model 2
    buf.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);

    // 2. Set error correction level M (49 = '1')
    buf.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]);

    // 3. Set module size (cell size in dots)
    final size = cmd.size.clamp(1, 16);
    buf.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size]);

    // 4. Store data
    final pL = dataLen & 0xFF;
    final pH = (dataLen >> 8) & 0xFF;
    buf.addAll([0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
    buf.addAll(data);

    // 5. Print
    buf.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);

    buf.addAll(_alignLeft);
    buf.addAll(_lf);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _writeDivider(List<int> buf, {bool dashed = false}) {
    final line = dashed
        ? ('- ' * (lineWidth ~/ 2)).substring(0, lineWidth)
        : '-' * lineWidth;
    buf.addAll(_encode(line));
    buf.addAll(_lf);
  }

  void _writeFeed(List<int> buf, int lines) {
    buf.addAll([0x1B, 0x64, lines]); // ESC d n — feed n lines
  }

  List<int> _alignBytes(ReceiptAlign align) => switch (align) {
        ReceiptAlign.left => _alignLeft,
        ReceiptAlign.center => _alignCenter,
        ReceiptAlign.right => _alignRight,
      };

  // Encode text to Latin-1 bytes for ESC/POS output.
  // Common Unicode punctuation is mapped to ASCII equivalents first so that
  // item names with smart quotes, dashes, or ellipses don't become '?'.
  // Remaining characters above U+00FF are replaced with '?'.
  List<int> _encode(String text) {
    final normalized = text
        .replaceAll('…', '...') // … ellipsis
        .replaceAll('’', "'")   // ' right single quote
        .replaceAll('‘', "'")   // ' left single quote
        .replaceAll('“', '"')   // " left double quote
        .replaceAll('”', '"')   // " right double quote
        .replaceAll('–', '-')   // – en-dash
        .replaceAll('—', '-')   // — em-dash
        .replaceAll(' ', ' ')   // non-breaking space
        .replaceAll('™', '(TM)') // ™
        .replaceAll('®', '(R)'); // ®
    try {
      return latin1.encode(normalized);
    } catch (_) {
      return normalized.runes.map((r) => r < 256 ? r : 0x3F).toList();
    }
  }
}
