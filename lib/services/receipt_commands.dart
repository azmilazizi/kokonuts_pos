import 'dart:typed_data';

enum ReceiptAlign { left, center, right }

sealed class ReceiptCmd {
  const ReceiptCmd();
}

class RcText extends ReceiptCmd {
  RcText(
    this.text, {
    this.align = ReceiptAlign.left,
    this.bold = false,
    this.large = false,
    this.small = false,
  });

  final String text;
  final ReceiptAlign align;
  final bool bold;
  final bool large; // double-size (header)
  final bool small; // condensed (modifier lines)
}

class RcRow extends ReceiptCmd {
  RcRow(this.left, this.right, {this.bold = false, this.rightAlignLabel = false});

  final String left;
  final String right;
  final bool bold;
  final bool rightAlignLabel;
}

class RcItemRow extends ReceiptCmd {
  const RcItemRow({
    required this.name,
    required this.price,
    required this.qty,
    required this.discount,
    required this.amount,
    this.isHeader = false,
  });

  final String name;
  final String price;
  final String qty;
  final String discount;
  final String amount;
  final bool isHeader;
}

class RcRow3 extends ReceiptCmd {
  RcRow3(this.left, this.middle, this.right, {this.bold = false});

  final String left;
  final String middle;
  final String right;
  final bool bold;
}

class RcImage extends ReceiptCmd {
  const RcImage(this.bytes, {this.align = ReceiptAlign.center});

  final Uint8List bytes;
  final ReceiptAlign align;
}

class RcQrCode extends ReceiptCmd {
  const RcQrCode(this.data, {this.size = 6});

  final String data;
  // Module size 1–16; 6 is roughly 35 × 35 mm on 58 mm paper.
  final int size;
}

class RcDivider extends ReceiptCmd {
  const RcDivider({this.dashed = false});
  final bool dashed;
}

class RcFeed extends ReceiptCmd {
  const RcFeed([this.lines = 1]);

  final int lines;
}

class RcCut extends ReceiptCmd {
  const RcCut();
}
