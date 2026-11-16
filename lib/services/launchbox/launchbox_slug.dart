/// File-safe name for a platform: "Sony Playstation 2" -> "sony_playstation_2".
///
/// Its own file so the store and the importer, which run without Flutter,
/// can use it without pulling in the console model.
String launchboxPlatformSlug(String platform) =>
    platform.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
