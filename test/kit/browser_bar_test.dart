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

  testWidgets('the menu is one icon after the actions', (t) async {
    var opened = 0;
    await pumpKit(t, Scaffold(body: BrowserBar(crumbs: const [Crumb('psx')], menu: () => opened++, menuTooltip: 'Folder options')));
    await t.tap(find.byTooltip('Folder options'));
    expect(opened, 1);
  });

  testWidgets('on a phone the actions go under the trail, which keeps the width', (t) async {
    await pumpKit(
      t,
      Scaffold(
        body: BrowserBar(
          crumbs: [Crumb('Internal', () {}), Crumb('ROMs', () {}), const Crumb('psx')],
          actions: [KitAction('New folder', () {}, icon: Icons.create_new_folder_outlined), KitAction('Storage', () {}, icon: Icons.sd_storage_outlined)],
          menu: () {},
        ),
      ),
      device: phone,
    );
    expect(t.getTopLeft(find.text('New folder')).dy, greaterThan(t.getBottomLeft(find.text('psx')).dy));
    expect(t.takeException(), isNull);
    await pumpKit(
      t,
      Scaffold(body: BrowserBar(crumbs: const [Crumb('psx')], actions: [KitAction('New folder', () {})])),
    );
    expect(t.getCenter(find.text('New folder')).dy, moreOrLessEquals(t.getCenter(find.text('psx')).dy, epsilon: 2));
  });

  testWidgets('a short trail starts at the left', (t) async {
    await pumpKit(t, Scaffold(body: BrowserBar(crumbs: [Crumb('Internal', () {}), const Crumb('ROMs')])));
    expect(t.getTopLeft(find.text('Internal')).dx, lessThan(40));
  });
}
