# Tinfoil Server — Design

Date: 2026-08-29
Status: approved in chat (brainstorming session)

## Goal

Let Tinfoil on a Nintendo Switch (same LAN) browse, download, and install
the Switch games listed in the app's catalog (`consoles.json`), including
sources that require authentication (Internet Archive S3, bearer tokens,
cookie tokens) which Tinfoil itself cannot send.

## How Tinfoil consumes a shop

- Tinfoil adds an HTTP source (`File Browser → + → protocol: http, host, port`).
- `GET /` must return a JSON index: `{"files": [{"url": "...", "size": N}, ...],
  "success": "message shown on the console"}`.
- Tinfoil downloads files over plain HTTP using `Range` requests and installs
  NSP/NSZ/XCI/XCZ directly — NSZ needs no server-side decompression.
- The display name comes from the last path segment of each file URL.

## Architecture

Embedded Dart HTTP server (`dart:io HttpServer`) inside the app. No new
dependencies. Runs on desktop and Android (Android keeps it alive with the
already-present `flutter_foreground_task`).

New units:

- `lib/services/tinfoil_server_service.dart` — `TinfoilServerService`:
  `start(port)` / `stop()`, owns the `HttpServer`, request routing, index
  generation, and the streaming proxy.
- `lib/providers/tinfoil_server_provider.dart` — Riverpod state: running,
  port, local IP addresses, active transfer count.
- `lib/screens/tinfoil_server_screen.dart` — control screen, opened from the
  3-dots overflow menu in the header (`lib/widgets/header/header.dart`).

Reused:

- `CatalogService.getConsoles()` / `loadCatalog(consoleId)` — game lists
  (served from the existing cache; loaded on demand on the first index hit).
- `utils/network.dart`: `buildConsoleAuthHeaders` (bearer + cookie auth),
  `buildDownloadHeaders`, `resolveRedirects` (auth headers are stripped on
  cross-host redirects, so the upstream URL is resolved first).
- IA S3 credentials from settings (`Authorization: LOW key:secret`), same as
  the download flow.

## Endpoints

### `GET /`

Tinfoil index. Includes every console whose `file_format` contains
`.nsp`, `.nsz`, `.xci`, or `.xcz`. For each game:

```json
{
  "files": [
    {"url": "http://<ip>:<port>/dl/<consoleId>/<gameIndex>/<filename>", "size": 123456}
  ],
  "success": "Retro Toolbox — N games"
}
```

Catalogs not yet cached are loaded on demand; consoles whose catalog fails to
load are skipped (logged, not fatal).

### `GET /dl/<consoleId>/<gameIndex>/<filename>`

Streaming proxy:

1. Look up the game in the in-memory map built during the last index
   generation (stable between `/` and `/dl` hits; 404 if unknown).
2. Build upstream headers: `buildDownloadHeaders` + console auth
   (`buildConsoleAuthHeaders` or IA `LOW`) — cookie-based auth included.
3. `resolveRedirects` on the upstream URL with those headers.
4. Forward the client's `Range` header upstream; stream the response back,
   preserving status (200/206), `Content-Length`, `Content-Range`, and
   `Accept-Ranges`.
5. Client disconnect aborts the upstream request. Upstream failure → 502.

Anything else → 404.

## UI

Overflow menu item **Tinfoil Server** → screen:

- Enable/disable switch. Port field (default 8000, persisted via
  SharedPreferences).
- When enabled: shows `http://<lan-ip>:<port>` for each non-loopback IPv4
  interface, plus the exact values to enter in Tinfoil
  (protocol `http`, host, port, path `/`).
- Active transfer counter.
- On Android, enabling starts a foreground service notification; disabling
  stops it.

Server lifetime is the app process; it does not auto-start on app launch.

## Error handling

- Port already in use → error shown on the screen, server stays off.
- Upstream auth/HTTP failure → 502 to Tinfoil, error logged.
- Console catalog load failure → console skipped in the index.
- App quit → server closed.

## Out of scope (v1)

- Non-Switch consoles in the shop (Tinfoil only installs Switch packages;
  pushing ROMs for emulators to the SD card is a separate future feature, e.g.
  FTP).
- Shop authentication, HTTPS, serving already-downloaded local files,
  NSP↔NSZ conversion.

## Testing

- Unit: index JSON generation from mocked games; Range header
  forwarding/response header passthrough logic.
- Manual: `curl http://localhost:8000/` returns valid index;
  `curl -r 0-1023 http://localhost:8000/dl/...` returns 206 with correct
  `Content-Range`; end-to-end install from a real Switch.
