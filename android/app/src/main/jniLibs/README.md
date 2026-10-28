# chdman for Android (jniLibs)

Android blocks executing binaries from writable app dirs, so chdman is shipped
as a **jniLib** and run from the read-only `nativeLibraryDir`.

`tool/build_chdman_android.sh` builds the arm64 binary (pinned source commit
and NDK r28, 16 KB page alignment) and drops it here, named `libchdman.so`:

    android/app/src/main/jniLibs/arm64-v8a/libchdman.so
    android/app/src/main/jniLibs/armeabi-v7a/libchdman.so   (optional, not built)

Requirements:
- Must be a position-independent executable built with the Android NDK for the
  matching ABI, linked for 16 KB pages (Play requires it; the script does both).
- Any shared libs it needs must also be shipped here as `lib*.so`.

`android:extractNativeLibs="true"` (set in AndroidManifest) makes Android unpack
these into `nativeLibraryDir` at install time. `ChdService` resolves
`<nativeLibraryDir>/libchdman.so` via the `retrotoolbox/native` method channel
and executes it directly.
