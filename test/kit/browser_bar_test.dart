import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  testWidgets('the trail goes to a folder on a tap; actions have names', (t) async {
    final went = <String>[];
    var made = 0;
    await pumpKit(
      t,
      Scaffold(
        body: BrowserBar(
          crumbs: [Crumb('Internal', () => went.add('Internal')), Crumb('ROMs', () => went.add('ROMs')), const Crumb('psx')],
          actions: [KitAction('New folder', () => made++, icon: Icons.create_new_folder_outlined)],
        ),
      ),
    );
    await t.tap(find.text('ROMs'));
    await t.tap(find.text('psx'));
    expect(went, ['ROMs']);
    await t.tap(find.text('New folder'));
    expect(made, 1);
  });

  testWidgets('a deep trail keeps the current folder in view', (t) async {
    await pumpKit(
      t,
      Scaffold(body: BrowserBar(crumbs: [for (var i = 0; i < 12; i++) Crumb('folder$i', () {})])),
      device: phone,
    );
    final last = t.getRect(find.text('folder11'));
    expect(last.right, lessThanOrEqualTo(412));
    expect(t.takeException(), isNull);
  });
}
