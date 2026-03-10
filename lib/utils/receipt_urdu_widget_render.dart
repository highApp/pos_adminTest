import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Renders Urdu (or any RTL) text to PNG by drawing with Flutter's widget tree.
/// Use this on Android where ParagraphBuilder + custom font often fails to render.
/// [context] must be from a widget that has an Overlay (e.g. the print preview dialog).
Future<Uint8List?> renderUrduTextToImageWithContext(
  BuildContext context, {
  required String text,
  double fontSize = 18,
  double maxWidth = 480,
}) async {
  if (text.isEmpty) return null;
  final overlay = Overlay.of(context);
  final key = GlobalKey();

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: -maxWidth - 100,
      top: -200,
      child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: maxWidth,
          height: 120,
          child: Container(
            color: Colors.white,
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Noto Nastaliq Urdu',
                fontSize: fontSize,
                color: Colors.black,
              ),
              textDirection: TextDirection.rtl,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);

  try {
    await Future.delayed(const Duration(milliseconds: 150));
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  } catch (e) {
    debugPrint('renderUrduTextToImageWithContext: $e');
    return null;
  } finally {
    entry.remove();
  }
}
