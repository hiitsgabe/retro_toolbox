/// A local folder the Retro Tools Server exposes as one console/system in the
/// generated catalog. [path] is the on-disk folder; the rest shape the entry
/// other apps see via New Catalog Source.
class RtsFolder {
  final String path;
  final String name;
  final List<String> formats;
  final String? boxartsUrl;
  final String romsSubfolder;

  const RtsFolder({
    required this.path,
    required this.name,
    this.formats = const [],
    this.boxartsUrl,
    required this.romsSubfolder,
  });

  RtsFolder copyWith({String? name, List<String>? formats, String? boxartsUrl, String? romsSubfolder}) => RtsFolder(
        path: path,
        name: name ?? this.name,
        formats: formats ?? this.formats,
        boxartsUrl: boxartsUrl ?? this.boxartsUrl,
        romsSubfolder: romsSubfolder ?? this.romsSubfolder,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'formats': formats,
        if (boxartsUrl != null) 'boxartsUrl': boxartsUrl,
        'romsSubfolder': romsSubfolder,
      };

  factory RtsFolder.fromJson(Map<String, dynamic> json) => RtsFolder(
        path: json['path'] as String,
        name: json['name'] as String,
        formats: (json['formats'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        boxartsUrl: json['boxartsUrl'] as String?,
        romsSubfolder: json['romsSubfolder'] as String? ?? json['name'] as String,
      );

  /// Best-guess LibRetro boxart base for [systemName]; users can edit it.
  static String libretroBoxarts(String systemName) =>
      'https://thumbnails.libretro.com/${Uri.encodeComponent(systemName)}/Named_Boxarts/';
}
