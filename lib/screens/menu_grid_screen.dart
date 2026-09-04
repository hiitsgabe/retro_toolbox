import 'package:flutter/material.dart';
import 'package:roms_downloader/widgets/menu_grid/menu_grid.dart';

/// Reusable grid page: an app bar title plus a [MenuGrid]. Used for the static
/// leaf menus (Servers, Ferramentas).
class MenuGridScreen extends StatelessWidget {
  final String title;
  final List<MenuTile> tiles;

  const MenuGridScreen({super.key, required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: MenuGrid(tiles: tiles),
    );
  }
}
