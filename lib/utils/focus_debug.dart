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
    debugPrint('[focus] ${ctx.widget.runtimeType} label=${node.debugLabel} rect=${node.rect} '
        'scroll=${scroll?.pixels.toStringAsFixed(1)}/${scroll?.maxScrollExtent.toStringAsFixed(1)} '
        'dpr=${view?.devicePixelRatio} size=${view == null ? null : MediaQuery.sizeOf(ctx)} '
        'path=${path.join('<')}');
  });
}
