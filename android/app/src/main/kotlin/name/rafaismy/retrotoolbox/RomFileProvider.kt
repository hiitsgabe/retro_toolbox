package name.rafaismy.retrotoolbox

import androidx.core.content.FileProvider

/// Serves a ROM on shared storage to an emulator that takes a content URI
/// (res/xml/rom_paths.xml). Its own class and authority, so the updater's
/// provider keeps its `updates/` scope alone.
class RomFileProvider : FileProvider()
