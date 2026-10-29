# Publishing on Google Play

The release workflow builds `retro_toolbox.aab` from the `play` flavor
(`flutter build appbundle --release --flavor play`). It differs from the
`direct` APKs in one way: `android/app/src/play/AndroidManifest.xml` drops
`REQUEST_INSTALL_PACKAGES`, and the in-app updater only links to the release
page (an app on Play may not update itself, and Play signs with its own key
anyway).

## Before the first upload

- **Play App Signing.** Upload the `.aab` and let Play re-sign it. Whatever
  signed the first upload becomes the *upload* key: the Expo-generated keystore
  on the Launch route, the CI keystore (`KEYSTORE64` secret) if the workflow's
  bundle is uploaded. Keep it; losing it means a key-reset request through Play
  support.
- **Target API.** The app targets 36 (`flutter.targetSdkVersion`), which meets
  the current requirement.
- **16 KB page size.** Required for apps targeting Android 15+. Every
  `lib/<abi>/*.so` in the bundle must be linked with 16 KB page alignment.
  All of them are: Flutter, the Python runtime and the `rar` plugin are built
  with NDK r28 (see `ndk` in `android/app/build.gradle`), and the bundled
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

## Building on Expo Launch

Launch runs a bare `flutter build appbundle --release` on the repo: no
`--flavor`, no staging step for the Python app, no files it could write into the
checkout. `android/app/build.gradle` (Groovy: Launch's steps append Groovy
`apply from:` lines to it, which a Kotlin DSL script cannot parse) covers that: a flavorless
`bundleRelease` builds only the `play` flavor and mirrors the result into
`bundle/release/` (where the Flutter tool looks when no flavor was given), and
Gradle stages the Python app and site-packages itself when the directories named
by the two `SERIOUS_PYTHON_*` variables are not there yet. The build takes its
settings from the project's EAS environment variables (expo.dev → project →
Environment variables, environment `production`):

| Variable | Value | Why |
|----------|-------|-----|
| `EAS_DANGEROUS_OVERRIDE_ANDROID_APPLICATION_ID` | `name.rafaismy.retrotoolbox` | eas-cli cannot read the applicationId from a Kotlin DSL script with flavors |
| `EAS_BUILD_DISABLE_MAVEN_CACHE` | `1` | EAS's Maven cache is injected through a Gradle init script that Flutter's Gradle plugin rejects (`FAIL_ON_PROJECT_REPOS`, flutter/flutter#174035) |
| `SERIOUS_PYTHON_APP` | `/home/expo/workingdir/build/build/serious_python_app` | where Gradle stages the Python app; absolute, under the worker's checkout (`/home/expo/workingdir/build`) |
| `SERIOUS_PYTHON_SITE_PACKAGES` | `/home/expo/workingdir/build/build/site-packages` | same, for the pip-installed packages |
| `KEY_STORE_PATH` (file), `KEY_STORE_PASSWORD` and `KEY_PASSWORD` (secret), `KEY_ALIAS` | the keystore Expo generated for the project, downloadable from its credentials page as `keystore.jks` plus a `credentials.json` holding `keystorePassword`, `keyPassword` and `keyAlias` | release signing unless Launch injects its own; `KEY_STORE_PASSWORD` only because that keystore's store and key passwords differ. Unsigned, the bundle is debug-signed and Play refuses it |

How Launch itself signs a Flutter project is not documented; the three signing
variables make the build independent of it. The Gradle log says which config
was used (`[Gradle] Using RELEASE signing config for build.`).

Differences from the workflow's `retro_toolbox.aab`: no bundled example catalog
(`EXAMPLE_DATA_URL` is only read by the workflow) and the desktop chdman assets
(about 5 MB) are not trimmed. `versionCode` is EAS's remote build number
(Launch's `eas/configure_android_version` step overrides it; it went 3, 4, …
on its own), and `versionName` is the pubspec version, which Launch passes as
`--build-name`. Launch also injects the keystore it generated (as
`credentials.json` plus a Groovy script applied after this one), so on Launch
the three signing variables above are only a fallback.

The same build runs locally, for checking:

    SERIOUS_PYTHON_APP=$PWD/build/launch/app SERIOUS_PYTHON_SITE_PACKAGES=$PWD/build/launch/site-packages \
      flutter build appbundle --release
