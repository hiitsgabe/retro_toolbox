# Google Cloud setup for Save Sync

Save Sync's default hub is a `Retro Toolbox Saves` folder in the user's own
Google Drive. The app signs in with its own OAuth client and asks for one
scope, `https://www.googleapis.com/auth/drive.file`, so it sees only the files
it created. There is no server: the token stays on the device and saves go
straight from the device to the user's Drive.

This file holds no client ids and no secrets: the repo is public, and the
Google APIs Terms of Service say developer credentials may not be embedded in
open source projects. The ids live in a GitHub Actions secret, an EAS
environment variable and a local file git ignores.

## One time, by the maintainer

Create the clients right before the first release that ships Save Sync with
Google Drive: Google deletes OAuth clients that see no use for six months.

1. Open console.cloud.google.com with the maintainer account (2-step
   verification on). Create a project, "Retro Toolbox".
2. APIs and Services, Library: enable "Google Drive API".
3. Google Auth Platform (console.cloud.google.com/auth/overview), Get started:
   app name "Retro Toolbox", user support email, Audience External, developer
   contact email.
4. Branding: home page `https://hiitsgabe.github.io/retro_toolbox/`, privacy
   policy `https://hiitsgabe.github.io/retro_toolbox/privacy.html`, authorized
   domain `hiitsgabe.github.io`. The logo is optional. Brand verification is
   optional too and only adds the name and logo to the consent screen.
5. Data Access: add `https://www.googleapis.com/auth/drive.file` and nothing
   else. It is a non-sensitive scope, so the app needs no verification. Asking
   in code for a scope that is not listed here shows users an "unverified app"
   screen.
6. Audience: Publish app, so the status reads "In production". Testing would
   cap the app at 100 test users and expire every grant after 7 days.
7. Clients, Create client:
   - Web application, for example "Save Sync server client", with no origins
     and no redirect URIs. Its client id is `GDRIVE_SERVER_CLIENT_ID`. Its
     secret is never used: do not copy it anywhere.
   - Android, package `name.rafaismy.retrotoolbox`, SHA-1 of the CI release
     keystore (the `direct` APKs from GitHub releases). Read it with
     `keytool -list -v -keystore <keystore file> -alias <KEY_ALIAS>` or
     `apksigner verify --print-certs retro_toolbox_universal.apk`
     (`keytool -printcert -jarfile` does not work: the APKs carry no v1
     signature).
   - Android, same package, SHA-1 of the Play app signing key: Play Console,
     the app, Test and release, Setup, App integrity, "App signing key
     certificate".
   - Android, same package, SHA-1 of the maintainer's debug keystore:
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`.
   All three share one project, so files one build creates are visible to
   the others.
8. Put the Web client id in three places:
   - GitHub: `gh secret set GDRIVE_SERVER_CLIENT_ID --repo hiitsgabe/retro_toolbox`
     (release.yml passes it to every Android build).
   - expo.dev, the project, Environment variables, `production`:
     `GDRIVE_SERVER_CLIENT_ID`, visibility Secret (the Play workflow passes it;
     see docs/play-store.md). The Play workflow's "Check the Google client id"
     step then logs `GDRIVE_SERVER_CLIENT_ID is set`; `EMPTY` means the bundle
     hides Google Drive.
   - Locally: copy `dart_defines.example.json` to `dart_defines.json` and fill
     it in, then `flutter run --flavor direct --dart-define-from-file=dart_defines.json`.

A build without the id (a fork, a plain local build) hides Google Drive and
offers only the folder hub. A fork signed with another key gets Google's
developer error at sign-in, which the app shows as "This build is not
registered with Google". If a client is ever abused: create a new one, ship a
build with it, then delete the old one.

## Privacy policy

`website/privacy.html` carries this paragraph (Google APIs Terms 3(d) and Play
both require it):

> Save Sync can keep game saves in a folder named "Retro Toolbox Saves" in
> your own Google Drive. It does so only after you choose "Sign in with
> Google" and allow it. The app asks only for Google's drive.file permission,
> so it can see and change only the files and folders it created itself, and
> nothing else in your Drive. The saves, and small files that list your
> devices (their names, models and app versions) and the games they sync, go
> straight from your device to your Drive. Your sign-in stays on your device,
> kept by Google Play services. No save, sign-in token or account detail
> reaches the developer or any server: there is none. Retro Toolbox's use and
> transfer of information received from Google APIs adheres to the Google API
> Services User Data Policy, including the Limited Use requirements. To stop,
> sign out in Save Sync; you can also remove the app's access in your Google
> Account under Security, Third-party connections. The folder stays in your
> Drive until you delete it. Save Sync's folder option uploads nothing itself:
> another app you choose carries that folder.

## Play Data safety form

Update it when the first Play release with Google Drive ships. Save Sync sends
files to the user's own Drive and nothing to the developer; declare it the way
Play's current form asks for data sent to a service the user signs in to, and
keep "no data shared with the developer".
