import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

/// Reusable grid page: an app bar title plus a [MenuGrid]. Used for the static
/// leaf menus (Servers, Ferramentas).
class MenuGridScreen extends StatelessWidget {
  final String title;
  final List<MenuTile> tiles;

  /// The order the user gives the tiles is saved under it (see [MenuGrid.menuId]).
  final String? menuId;

  const MenuGridScreen({super.key, required this.title, required this.tiles, this.menuId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: MenuGrid(menuId: menuId, tiles: tiles),
    );
  }
}
