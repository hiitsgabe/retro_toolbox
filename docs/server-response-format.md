# Server Response Format

This document describes how your server needs to respond for Retro Toolbox to detect and list files. Three response formats are supported: **HTML Directory Listing**, **JSON API**, and **Internet Archive**.

---

## HTML Directory Listing (Recommended)

The most common format. Your server serves an HTML page containing links to files, and the app uses a regex pattern to extract file information from each entry.

### Expected HTML Structure

The app fetches the page at the configured `url` and applies a regex to extract file entries. Here's an example of a valid response:

```html
<!DOCTYPE html>
<html>
<body>
  <h1>Index of /files/My-System/</h1>
  <table>
    <thead>
      <tr>
        <th>File Name</th>
        <th>File Size</th>
        <th>Date</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td class="link">
          <a href="Game%20Name%20%28USA%29.zip" title="Game Name (USA).zip">
            Game Name (USA).zip
          </a>
        </td>
        <td class="size">125.4 MiB</td>
        <td class="date">15-Jan-2025 12:00</td>
      </tr>
      <tr>
        <td class="link">
          <a href="Another%20Game%20%28USA%29.zip" title="Another Game (USA).zip">
            Another Game (USA).zip
          </a>
        </td>
        <td class="size">89.2 MiB</td>
        <td class="date">20-Feb-2025 08:30</td>
      </tr>
    </tbody>
  </table>
</body>
</html>
```

### Regex Pattern

The regex must use **named capture groups** to extract data. Recognized group names:

| Group Name   | Required | Description |
|--------------|----------|-------------|
| `href`       | Yes*     | The download URL (relative or absolute path) |
| `text`       | No       | Display filename (falls back to `title`, then `href`) |
| `title`      | No       | Fallback display name |
| `size`       | No       | Human-readable file size |
| `id`         | Yes*     | Unique identifier, used with `download_url` template |
| `banner_url` | No       | URL to a thumbnail/banner image for the file |

\* Either `href` or `id` (with `download_url`) is required.

The regex matching the HTML structure above:

```
<tr><td class="link"><a href="(?P<href>[^"]+)" title="(?P<title>[^"]+)">(?P<text>[^<]+)</a></td><td class="size">(?P<size>[^<]+)</td><td class="date">[^<]*</td></tr>
```

### Default Fallback

If no custom `regex` is configured, the app falls back to a Myrient-style pattern that matches `<tr><td class="link">...` rows and filters by `file_format`. This works out of the box with most standard directory listing servers.

### Key Requirements

1. File links must contain the filename (or URL-encoded version) in the `href` attribute
2. Relative URLs are supported — the app joins them with the base `url`
3. Filenames with special characters should be URL-encoded in `href` (spaces as `%20`)
4. The `title` attribute should contain the decoded, readable filename
5. Your server should respond to `HEAD` requests with a `Content-Length` header so the app can show file sizes and progress

### Download URL Template

For servers where the download URL differs from the listing URL, use `download_url` with an `<id>` placeholder:

```json
{
  "url": "https://your-server.com/api/games",
  "regex": "\"(?P<id>[A-F0-9]+)\".*?\"name\".*?\"(?P<text>[^\"]+)\"",
  "download_url": "https://your-server.com/download/<id>/file"
}
```

When the regex captures an `id` group, the app substitutes it into the template to build the final download link.

---

## JSON API

For servers that return structured JSON instead of HTML.

### Configuration

Use `list_url` instead of `url` to indicate a JSON API source:

```json
{
  "name": "My System",
  "list_url": "https://your-api.com/games/?limit=100000",
  "list_json_file_location": "files",
  "list_item_id": "name",
  "file_format": [".zip"],
  "roms_folder": "my_system"
}
```

### Expected JSON Response

```json
{
  "files": [
    { "name": "Game One (USA).zip" },
    { "name": "Game Two (USA).zip" },
    { "name": "Game Three (Europe).zip" }
  ]
}
```

### Configuration Fields

| Field | Default | Description |
|-------|---------|-------------|
| `list_url` | *(required)* | Full URL to the JSON API endpoint |
| `list_json_file_location` | `"files"` | Top-level key in the response that holds the files array |
| `list_item_id` | `"name"` | Key within each file object that contains the filename |

### Custom Response Structure

```json
{
  "list_url": "https://api.example.com/v1/games",
  "list_json_file_location": "games",
  "list_item_id": "filename"
}
```

> **Note**: `list_json_file_location` resolves a single top-level key. Nested paths are not supported.

---

## Internet Archive

For items hosted on archive.org. The app detects `archive.org/download/` URLs automatically and uses the IA metadata API — no regex needed.

### Configuration

```json
{
  "name": "My Collection",
  "url": "https://archive.org/download/my-item-id",
  "file_format": [".zip", ".iso"],
  "roms_folder": "my_system"
}
```

### Multi-Part Collections

```json
{
  "name": "Large Collection",
  "url": [
    "https://archive.org/download/my-collection-part1",
    "https://archive.org/download/my-collection-part2",
    "https://archive.org/download/my-collection-part3"
  ],
  "file_format": [".zip"],
  "roms_folder": "my_system"
}
```

File lists from all items are merged alphabetically. Download URLs are resolved per-item, so files from different items download correctly.

### Authentication

For private or restricted items:

```json
{
  "url": "https://archive.org/download/my-private-item",
  "auth": {
    "type": "ia_s3",
    "access_key": "your-access-key",
    "secret_key": "your-secret-key"
  }
}
```

S3 credentials can also be configured globally in General Settings → Internet Archive, and used by any system with `"type": "ia_s3"` auth.

---

## Authentication

All three formats support optional authentication via an `auth` object on the system config.

### Bearer Token

```json
{ "auth": { "token": "your-bearer-token" } }
```

Sent as: `Authorization: Bearer your-bearer-token`

### Cookie-Based

```json
{ "auth": { "cookies": true, "cookie_name": "session_id", "token": "your-session-token" } }
```

Sent as a cookie: `session_id=your-session-token`

### Sign-In Flow

For systems that require the user to log in with credentials:

```json
{
  "auth": {
    "cookies": true,
    "cookie_name": "auth_token",
    "token": "",
    "auth_message": "Instructions shown to the user in settings.",
    "signin": {
      "register_url": "https://example.com/register",
      "url": "https://api.example.com/auth/login",
      "method": "POST",
      "params": ["username", "password"],
      "token_regex": "\"access_token\"\\s*:\\s*\"([^\"]+)\""
    }
  }
}
```

The app renders one input field per name in `params` plus a *Create account* link. On submit, it calls the `url` endpoint with a form-encoded body; the token is extracted from the response via `token_regex` (capture group 1) and saved. Credentials are not stored.

### Internet Archive S3

```json
{ "auth": { "type": "ia_s3", "access_key": "your-access-key", "secret_key": "your-secret-key" } }
```

Sent as: `Authorization: LOW access-key:secret-key`

---

## Filtering Behavior

The app applies these filters to the parsed file list before display:

1. **Extension filtering** — Only files matching `file_format` extensions are shown (case-insensitive). Disable with `"ignore_extension_filtering": true`.
2. **USA/region filter** — When enabled in settings, hides files not matching a region regex (default: `(USA)`). Configurable per-system with `usa_regex`.
3. **Non-ASCII filter** — Files starting with non-ASCII characters are skipped.
4. **Sorting** — Results are sorted alphabetically by filename.

---

## Testing Your Server

Verify your server responds correctly from the command line:

```bash
# Fetch the HTML listing
curl -s "https://your-server.com/files/system/" | head -30

# Test regex matching
curl -s "https://your-server.com/files/system/" | \
  grep -oP '<tr><td class="link"><a href="(?P<href>[^"]+)"'

# Test JSON response structure
curl -s "https://your-api.com/games/" | python3 -m json.tool

# Verify HEAD support (for file size display)
curl -I "https://your-server.com/files/system/Game.zip"
```
