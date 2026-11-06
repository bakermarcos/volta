import 'dart:math' as math;

import '../game/circuit.dart';

import 'package:flutter/material.dart';

import 'package:qr/qr.dart';

const ink = Color(0xFF111918);
const panel = Color(0xFF1B2623);
const lime = Color(0xFFBDFE55);
const muted = Color(0xFFA2B2A7);

class VoltaMark extends StatelessWidget {
  const VoltaMark({super.key, this.height = 36});
  final double height;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/volta_logo.png',
    height: height,
    fit: BoxFit.contain,
    alignment: Alignment.centerLeft,
    semanticLabel: 'Volta',
  );
}

class RoomQr extends StatelessWidget {
  const RoomQr(this.code, {super.key, this.size = 176});
  final String code;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'QR para entrar na sala $code',
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size < 150 ? 10 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: CustomPaint(painter: _QrPainter(code)),
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(String code)
    : qr = QrImage(
        QrCode(
          payload: QrPayload.fromString(code),
          errorCorrectLevel: QrErrorCorrectLevel.medium,
        ),
      );
  final QrImage qr;
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / (qr.moduleCount + 8);
    for (var y = 0; y < qr.moduleCount; y++) {
      for (var x = 0; x < qr.moduleCount; x++) {
        if (qr.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH((x + 4) * unit, (y + 4) * unit, unit + .1, unit + .1),
            Paint()..color = ink,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.qr != qr;
}

class CircuitThumbnail extends CustomPainter {
  CircuitThumbnail(this.circuit, {required this.color});
  final Circuit circuit;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      (size.width - 8) / (circuit.maxX - circuit.minX),
      (size.height - 8) / (circuit.maxY - circuit.minY),
    );
    final centerX = (circuit.minX + circuit.maxX) / 2,
        centerY = (circuit.minY + circuit.maxY) / 2;
    final path = Path();
    for (var i = 0; i < circuit.points.length; i++) {
      final p = circuit.points[i];
      final x = size.width / 2 + (p.x - centerX) * scale,
          y = size.height / 2 + (p.y - centerY) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.min(8, math.max(4, circuit.width * scale))
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(CircuitThumbnail oldDelegate) =>
      oldDelegate.circuit != circuit || oldDelegate.color != color;
}
