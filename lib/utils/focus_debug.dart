import 'dart:io';

import 'package:flutter/widgets.dart';

/// Logs every focus change with the focused widget, its rect and the nearest
/// scroll position when `RETRO_TOOLBOX_DEBUG_FOCUS=1`. For diagnosing d-pad
/// issues on devices where we only have a log.
void installFocusDebug() {
  if (Platform.environment['RETRO_TOOLBOX_DEBUG_FOCUS'] != '1') return;
  FocusManager.instance.addListener(() {
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (node == null || ctx == null) {
      debugPrint('[focus] none');
      return;
    }
    final path = <String>[];
    ctx.visitAncestorElements((e) {
      if (path.length < 6) path.add(e.widget.runtimeType.toString());
      return path.length < 6;
    });
    final scroll = Scrollable.maybeOf(ctx)?.position;
    final view = View.maybeOf(ctx);
    final size = view == null ? null : MediaQuery.sizeOf(ctx);
    // Release builds print Rect/Size as "Instance of ...": format by hand.
    String f(double v) => v.toStringAsFixed(1);
    final r = node.rect;
    debugPrint('[focus] ${ctx.widget.runtimeType} label=${node.debugLabel} '
        'rect=${f(r.left)},${f(r.top)} ${f(r.width)}x${f(r.height)} '
        'scroll=${scroll == null ? '-' : '${f(scroll.pixels)}/${f(scroll.maxScrollExtent)}'} '
        'dpr=${view?.devicePixelRatio} size=${size == null ? '-' : '${f(size.width)}x${f(size.height)}'} '
        'path=${path.join('<')}');
  });
}
