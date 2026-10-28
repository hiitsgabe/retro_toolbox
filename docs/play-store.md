# Publishing on Google Play

The release workflow builds `retro_toolbox.aab` from the `play` flavor
(`flutter build appbundle --release --flavor play`). It differs from the
`direct` APKs in one way: `android/app/src/play/AndroidManifest.xml` drops
`REQUEST_INSTALL_PACKAGES`, and the in-app updater only links to the release
page (an app on Play may not update itself, and Play signs with its own key
anyway).

## Before the first upload

- **Play App Signing.** Upload the `.aab` and let Play re-sign it. The CI
  keystore (`KEYSTORE64` secret) becomes the *upload* key: keep it, losing it
  means a key-reset request through Play support.
- **Target API.** The app targets 36 (`flutter.targetSdkVersion`), which meets
  the current requirement.
- **16 KB page size.** Required for apps targeting Android 15+. Every
  `lib/<abi>/*.so` in the bundle must be linked with 16 KB page alignment.
  All of them are: Flutter, the Python runtime and the `rar` plugin are built
  with NDK r28 (see `ndk` in `android/app/build.gradle.kts`), and the bundled
  chdman (`android/app/src/main/jniLibs/arm64-v8a/libchdman.so`) is built by
  `tool/build_chdman_android.sh` with the same NDK (every PT_LOAD segment
  aligned to 0x4000). Check a built bundle with Android's
  `check_elf_alignment.sh` (from the 16 KB page size guide) on the extracted
  `base/lib/arm64-v8a/` folder.
- **versionCode** must only go up. The release workflow bumps the pubspec
  build number on every release; Play refuses a bundle with a number it has
  already seen.

## Permission declarations (Play Console → App content)

### All files access (`MANAGE_EXTERNAL_STORAGE`)

Core use case: **File manager**. Suggested justification:

> Retro Toolbox is a file-management tool for retro game libraries kept on
> shared storage, SD cards and USB drives. Its core features are file
> operations on folders the user chooses, which other apps (emulators, file
> managers, downloads) create and read: browsing and organizing a library,
> moving and renaming files, extracting ZIP/7z/RAR archives in place,
> converting disc images to CHD next to the originals with the bundled chdman
> tool, patching roster files in place, and serving or receiving files over the
> local network (FTP, WebDAV, SMB). The app needs real file paths: the bundled
> native tools (chdman, the Python patchers) operate on files directly and
> cannot take Storage Access Framework URIs, and MediaStore does not index
> these file types (.chd, .cue/.bin, .iso, .zip, .7z, .rar, ROM files). The
> permission is used only for the folders the user opens in the app. Files are
> never sent to the developer or to any internet service; local-network sharing
> happens only while the user runs one of the app's servers.

A short screen recording is required: show the file browser opening a folder on
the SD card, an archive being extracted there, and the CHD converter writing
next to the source file.

### Foreground services

Declared types (`android/app/src/main/AndroidManifest.xml`): `dataSync` on the
download and task services, plus `remoteMessaging` on the task service. Play
asks for a purpose and a video per type.

- `dataSync`: downloads, extractions and conversions keep running with a
  progress notification while the app is in the background.
- `remoteMessaging` is meant for apps that relay text messages between
  devices. If nothing in the app needs it, drop it from the service and the
  `FOREGROUND_SERVICE_REMOTE_MESSAGING` permission before submitting; Play
  reviews each type and this one is a likely rejection.

## Also required for the listing

- A privacy policy URL (every app). A page on the project website is enough.
- The Data safety form: the app contacts the release page for update checks
  and whatever catalog sources the user adds; it sends no user data to the
  developer.
- Store listing assets: icon (512 px), feature graphic, screenshots.
