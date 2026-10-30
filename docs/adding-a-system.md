# Adding a System

Retro Toolbox can pull game lists from different kinds of servers. This guide walks you through each supported source type and how to configure them.

The configuration format is the same as the one used by the PyGame companion app (Console Utilities), so JSON files can be shared between both apps.

---

## Where to Put Your Configuration

Systems are defined as a JSON array in a configuration file. Each element in the array is one system.

The app looks for `consoles.json` in two places, in order:

1. **User config directory** — `{app_support}/config/consoles.json`. Files placed here override the bundled data.
2. **Bundled asset** — the `assets/consoles.json` file shipped with the app.

A minimal file looks like this:

```json
[
  { "name": "SNES", "url": "https://your-server.com/snes/", "original_format": [".zip"], "decompress": "unzip", "roms_folder": "snes" },
  { "name": "Game Boy", "url": "https://your-server.com/gb/", "original_format": [".zip"], "decompress": "unzip", "roms_folder": "gb" }
]
```

---

## Source Types

The app supports three ways to fetch a game list. It picks the parser based on the fields you provide:

| You provide...                            | The app uses...         |
|-------------------------------------------|-------------------------|
| `url` pointing to `archive.org/download/...` | **Internet Archive** parser |
| `list_url`                                | **JSON API** parser     |
| `url` pointing to anything else           | **HTML** parser         |

---

## 1. HTML Directory Listing

The most common setup. The app fetches an HTML page, scans it with a regex pattern, and extracts the file list.

### How it works

1. The app makes a GET request to `url`
2. It runs a regex pattern across the HTML response
3. Each match becomes a game entry — the pattern pulls out the filename, download link, and optionally the file size
4. Results are filtered by `original_format` and sorted alphabetically

### Basic example

If your server has a simple directory listing with `<a>` tags, you don't need a custom regex:

```json
{
  "name": "SNES",
  "url": "https://your-server.com/roms/snes/",
  "platform": "snes",
  "original_format": [".zip"],
  "decompress": "unzip",
  "game_files_format": [".sfc", ".smc"],
  "roms_folder": "snes"
}
```

Without a `regex` field, the app falls back to a pattern that matches directory-listing-style HTML tables (`<tr><td class="link">...`). It then filters by `original_format`.

### Custom regex

For servers with different HTML layouts, provide a regex with **named capture groups**:

```json
{
  "name": "SNES",
  "url": "https://your-server.com/files/SNES/",
  "regex": "<tr><td class=\"link\"><a href=\"(?P<href>[^\"]+)\" title=\"(?P<title>[^\"]+)\">(?P<text>[^<]+)</a></td><td class=\"size\">(?P<size>[^<]+)</td><td class=\"date\">[^<]*</td></tr>",
  "platform": "snes",
  "original_format": [".zip"],
  "decompress": "unzip",
  "game_files_format": [".sfc", ".smc"],
  "roms_folder": "snes"
}
```

Supported capture group names:

| Group       | Required | What it does |
|-------------|----------|--------------|
| `href`      | Yes*     | The download link (relative or absolute URL) |
| `text`      | No       | The display filename. Falls back to `title`, then `href` |
| `title`     | No       | Alternative display name |
| `size`      | No       | Human-readable file size |
| `id`        | Yes*     | Unique file identifier — used with `download_url` |
| `banner_url`| No       | URL to a thumbnail image for this file |

\* Either `href` or `id` (with `download_url`) is required.

### Custom download URLs

When the listing page and the actual download endpoint differ, use `download_url` with an `<id>` placeholder:

```json
{
  "name": "Custom API",
  "url": "https://api.example.com/catalog",
  "regex": "\"(?P<id>[A-F0-9]+)\".*?\"name\":\"(?P<text>[^\"]+)\"",
  "download_url": "https://api.example.com/download/<id>/file",
  "original_format": [".zip"],
  "roms_folder": "custom",
  "ignore_extension_filtering": true
}
```

---

## 2. Internet Archive

For files hosted on `archive.org`, the app uses the Internet Archive metadata API automatically — no regex needed.

### Basic example

```json
{
  "name": "My Collection",
  "url": "https://archive.org/download/my-collection-id",
  "original_format": [".zip"],
  "decompress": "unzip",
  "game_files_format": [".bin", ".cue"],
  "roms_folder": "my_collection"
}
```

### Private/restricted items

For items that require authentication, add IA S3 credentials:

```json
{
  "name": "My Private Collection",
  "url": "https://archive.org/download/my-private-item",
  "original_format": [".zip"],
  "roms_folder": "my_collection",
  "auth": {
    "type": "ia_s3",
    "access_key": "your-access-key",
    "secret_key": "your-secret-key"
  }
}
```

---

## 3. JSON API

For servers that return a structured JSON response instead of HTML.

### Basic example

```json
{
  "name": "My Game Library",
  "list_url": "https://api.example.com/games/?limit=100000",
  "list_json_file_location": "files",
  "list_item_id": "name",
  "original_format": [".zip"],
  "roms_folder": "my_library",
  "decompress": "unzip"
}
```

This expects a response like:

```json
{
  "files": [
    { "name": "Game One (USA).zip" },
    { "name": "Game Two (USA).zip" }
  ]
}
```

### Configuration fields

| Field                     | Default    | Description |
|---------------------------|------------|-------------|
| `list_url`                | *(required)* | Full URL to the JSON endpoint |
| `list_json_file_location` | `"files"`  | Top-level key in the response that holds the files array |
| `list_item_id`            | `"name"`   | Key within each file object that contains the filename |

---

## Multi-Part Collections

Some collections are split across multiple URLs. Use an array in the `url` field — the app fetches each one and merges the results:

```json
{
  "name": "My Large System",
  "url": [
    "https://archive.org/download/my-collection-part1/",
    "https://archive.org/download/my-collection-part2/",
    "https://archive.org/download/my-collection-part3/"
  ],
  "original_format": [".zip"],
  "roms_folder": "my_system",
  "decompress": "unzip"
}
```

---

## Common Fields Reference

### Required

| Field         | Type             | Description |
|---------------|------------------|-------------|
| `name`        | string           | Display name shown in the console selector |
| `roms_folder` | string           | Target directory for downloads (folder name or absolute path) |
| `original_format` | array of strings | What the server delivers, e.g. `[".zip"]` or `[".iso"]`. Filters the listing. |

Plus a source — either `url` (for HTML or Internet Archive) or `list_url` (for JSON API).

### Optional

| Field                      | Type    | Default       | Description |
|----------------------------|---------|---------------|-------------|
| `regex`                    | string  | directory-listing-style | Custom regex for HTML parsing |
| `boxarts`                  | string  | *(none)*      | Base URL for thumbnails |
| `platform`                 | string  | *(guessed)*   | Batocera system id (`psx`, `switch`…); see below |
| `decompress`               | string  | `"none"`      | `unzip`, `unrar` or `none` |
| `game_files_format`        | array   | *(keep all)*  | What stays after decompressing; the rest is deleted |
| `additional_handler`       | string  | *(none)*      | `chd_compress`, `3ds_convert` or `nsz_decompress` |
| `extract_contents`         | boolean | `true`        | Extract only contents, not the wrapper folder |
| `should_filter_usa`        | boolean | `true`        | Whether the USA-only filter applies to this system |
| `usa_regex`                | string  | `"(USA)"`     | Custom regex for region filtering |
| `ignore_extension_filtering` | boolean | `false`     | Show all regex matches regardless of `original_format` |
| `download_url`             | string  | *(none)*      | Download URL template with `<id>` placeholder |
| `auth`                     | object  | *(none)*      | Authentication config (see below) |

---

## Formats, Decompression and Conversion

Each system describes the path a game takes from the server to the ROM folder:

| Field | Meaning |
|-------|---------|
| `platform` | Batocera system id (`psx`, `ps2`, `switch`, `3ds`, `megadrive`, `gamecube`…). Drives the logo, colors and which local servers list the system. Without it, the app guesses from the name, then from the formats. |
| `original_format` | What the server delivers: an archive (`.zip`, `.rar`) or the game's own format. Only these files are listed. |
| `decompress` | `unzip`, `unrar` or `none` (the default). A file that doesn't match the method is kept as downloaded. |
| `game_files_format` | Optional. What stays after decompressing; everything else in the archive is deleted. |
| `additional_handler` | Optional. A conversion that runs last, on the files it accepts. |

Handlers:

| Handler | Takes | Makes | Needs |
|---------|-------|-------|-------|
| `chd_compress` | `.cue`, `.gdi`, `.iso` | `.chd` | chdman |
| `3ds_convert` | `.3ds`, `.cci` | `.cia` | boot9.bin for encrypted dumps |
| `nsz_decompress` | `.nsz` | `.nsp` | prod.keys |

The input files are deleted only after their conversion succeeds. If the tool is missing or the conversion fails, the game stays in its `game_files_format`. Users can turn each handler on or off per system in Settings → Conversion.

A disc system delivered as zips and stored as CHD:

```json
{
  "name": "My Disc System",
  "url": "https://your-server.com/discs/",
  "platform": "psx",
  "original_format": [".zip"],
  "decompress": "unzip",
  "game_files_format": [".bin", ".cue"],
  "additional_handler": "chd_compress",
  "roms_folder": "psx"
}
```

### Older keys

Configs written for earlier versions still work. When a new key is missing, it is filled from the old ones:

| Old | New |
|-----|-----|
| `file_format` + `should_unzip: true` (no `download_url`) | `original_format: [".zip"]`, `decompress: "unzip"`, `game_files_format: file_format` |
| `file_format` otherwise | `original_format: file_format` |
| `should_decompress_nsz: true`, or `.nsz` in `file_format` | `additional_handler: "nsz_decompress"` |
| `convert_3ds_to_cia: true` | `additional_handler: "3ds_convert"` |

---

## Authentication

All source types support optional authentication:

### Bearer Token

```json
{ "auth": { "token": "your-bearer-token" } }
```

Sent as `Authorization: Bearer your-bearer-token` on every request.

### Cookie-Based

```json
{ "auth": { "cookies": true, "cookie_name": "session_id", "token": "your-session-token" } }
```

Sent as a cookie: `session_id=your-session-token`.

### Internet Archive S3

```json
{ "auth": { "type": "ia_s3", "access_key": "your-access-key", "secret_key": "your-secret-key" } }
```

Sent as `Authorization: LOW access-key:secret-key`.

---

## Boxart / Thumbnails

The `boxarts` field sets a base URL for cover art. The app builds thumbnail URLs by appending the game filename (with `.png` extension) to this base:

```json
"boxarts": "https://thumbnails.example.com/SNES/"
```

A game named `"Cool Game (USA).zip"` would look for a thumbnail at:

```
https://thumbnails.example.com/SNES/Cool Game (USA).png
```

---

## System Discovery (Advanced)

If you're hosting a server and want users to browse and add systems from within the app, configure a discovery endpoint by adding an entry with `"list_systems": true`:

```json
{
  "name": "Available Systems",
  "list_systems": true,
  "url": "https://your-server.com/files/systems/",
  "regex": "<tr><td class=\"link\"><a href=\"(?P<href>[^\"]+)\" title=\"(?P<title>[^\"]+)\">(?P<text>[^<]+)</a></td><td class=\"size\">(?P<size>[^<]+)</td><td class=\"date\">[^<]*</td></tr>",
  "original_format": [".zip"],
  "decompress": "unzip",
  "boxarts": "https://thumbnails.example.com/"
}
```

Entries with `list_systems: true` are never shown in the main console list — they exist only to power a discovery flow.

---

## Troubleshooting

**System shows no games:**
- Open the `url` in a browser to verify it's accessible
- If using a custom `regex`, test it against the page HTML
- Check that `original_format` extensions match actual files on the server

**Games download to wrong folder:**
- Double-check `roms_folder` matches what your emulator expects

**Thumbnails not loading:**
- Verify the `boxarts` base URL is correct
- Thumbnail filenames must match game filenames (minus extension, plus `.png`)
