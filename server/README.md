# Retro Toolbox server (Docker)

Runs the Linux desktop build headless on a Linux x64 host and shows it in the browser.
KasmVNC provides the virtual display and the web client (HTTPS, password, clipboard sync);
a watchdog restarts the app if it exits or keeps using too much memory while idle.

Requirements: a Linux x86-64 host with Docker and Compose.

## Install

```sh
mkdir retro-toolbox && cd retro-toolbox
# copy docker-compose.yml from this folder, then:
echo 'RETRO_TOOLBOX_PASSWORD=choose-a-password' > .env
sudo mkdir -p /srv/roms && sudo chown 1000:1000 /srv/roms
docker compose up -d
```

Open `https://<host>:8444`, accept the self-signed certificate, and log in as user `retro`
with your password. The app fills the browser window and follows its size.

## Variables

| Variable | Default | |
|---|---|---|
| `RETRO_TOOLBOX_PASSWORD` | (required) | Web page password, at least 6 characters. The container exits with an error without it. Changing it takes effect on the next start. |
| `RETRO_TOOLBOX_PORT` | `8444` | HTTPS port of the web page. |
| `RETRO_TOOLBOX_MEMORY_LIMIT_MB` | `2048` | Watchdog: restart the app after 3 checks (60 s apart) above this RSS, only while idle. Keep `mem_limit` above it. |

Set by the image, don't change: `RETRO_TOOLBOX_SERVER=1`, `RETRO_TOOLBOX_BUSY_FILE=/tmp/retro_toolbox.busy`.

## Volumes and folder permissions

- `/data` is the home folder of the container user (`retro`, uid/gid 1000): settings, cache,
  the default downloads folder and the web certificate (`/data/.kasmvnc/`). Keep it on a named
  volume so it survives updates.
- Mount ROM folders wherever you like (the example uses `/roms`). The app's file browser and file
  pickers see the container's disk, so pick `/roms`, not the host path. In a file picker,
  Ctrl+L lets you type a path.
- Mounted folders must be writable by uid 1000: `sudo chown -R 1000:1000 /srv/roms`.

The container uses `network_mode: host`, so the app's servers listen on the host's IP and
consoles on the network reach them directly.

## Clipboard

- Chrome and Edge: copy/paste between your computer and the app works directly (the page must be
  HTTPS; allow clipboard access when the browser asks).
- Firefox: no automatic sync. Open the side panel of the web client and use its clipboard box.

## Update

```sh
docker compose pull && docker compose up -d
```

## Building the image

The build context is this folder with the Linux release tarball dropped in:

```sh
cp retro_toolbox_linux_x64.tar.gz server/
docker build --platform linux/amd64 -f server/Dockerfile -t retro-toolbox-server:dev server
```

The KasmVNC version is the `KASMVNC_VERSION` build arg in the Dockerfile.

## Publishing

The release workflow pushes the image to GHCR after the release succeeds. After the first publish,
make the package public once in its GHCR package settings so `docker compose pull` works without a login.

## Manual checks

Not yet done on a real x64 host:

- [ ] Chrome: paste text from the computer into an app text field, copy it back out.
- [ ] Firefox: the same through the web client's clipboard panel.
- [ ] Rendering with llvmpipe is acceptable on real hardware (only checked under emulation).
- [ ] The screen that uses `flutter_inappwebview` behaves as in the Linux desktop build.
- [ ] Turn on a console server, restart the container, it comes back on (needs a release with server mode).
- [ ] A console on the LAN reaches the server and the IP shown is the host's.
- [ ] RSS in normal use (`grep VmRSS /proc/$(pgrep -x retro_toolbox)/status`) is well under the 2048 MB default.
