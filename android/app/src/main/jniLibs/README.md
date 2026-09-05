# chdman for Android (jniLibs)

Android blocks executing binaries from writable app dirs, so chdman is shipped
as a **jniLib** and run from the read-only `nativeLibraryDir`.

Drop a chdman binary built for each ABI here, named `libchdman.so`:

    android/app/src/main/jniLibs/arm64-v8a/libchdman.so
    android/app/src/main/jniLibs/armeabi-v7a/libchdman.so   (optional)

Requirements:
- Must be a position-independent executable built with the Android NDK for the
  matching ABI (see the CHDroid project for a working build recipe).
- Any shared libs it needs must also be shipped here as `lib*.so`.

`android:extractNativeLibs="true"` (set in AndroidManifest) makes Android unpack
these into `nativeLibraryDir` at install time. `ChdService` resolves
`<nativeLibraryDir>/libchdman.so` via the `retrotoolbox/native` method channel
and executes it directly.
