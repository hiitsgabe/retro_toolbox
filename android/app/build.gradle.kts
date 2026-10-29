import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (the release workflow writes it from
// the KEYSTORE64/KEY_STORE_PATH/KEY_PASSWORD/KEY_ALIAS secrets; Flutter's own
// template uses storePassword/keyPassword), or those secret names as plain
// environment variables for builders that cannot write files into the checkout
// (Expo Launch: KEY_STORE_PATH as a file variable). KEY_STORE_PASSWORD is only
// needed when the store and key passwords differ, as they do in the keystore
// Expo generates. Neither source: debug signing.
val keystoreProperties = Properties()
rootProject.file("key.properties").takeIf { it.exists() }?.let { keystoreProperties.load(FileInputStream(it)) }
val env = System.getenv()
val releaseStoreFile = (keystoreProperties.getProperty("storeFile") ?: env["KEY_STORE_PATH"])?.let { rootProject.file(it) }
val releaseStorePassword = keystoreProperties.getProperty("storePassword")
    ?: keystoreProperties.getProperty("password") ?: env["KEY_STORE_PASSWORD"] ?: env["KEY_PASSWORD"]
val releaseKeyPassword = keystoreProperties.getProperty("keyPassword")
    ?: keystoreProperties.getProperty("password") ?: env["KEY_PASSWORD"] ?: releaseStorePassword
val releaseKeyAlias = keystoreProperties.getProperty("keyAlias") ?: env["KEY_ALIAS"]
val releaseSigning = releaseStoreFile != null && releaseStorePassword != null && releaseKeyAlias != null

// NDK r28 links native code for 16 KB pages, which Play requires of apps
// targeting Android 15+. Flutter 3.35's default is still r27 (4 KB).
val ndk = "28.2.13676358"

android {
    namespace = "name.rafaismy.retrotoolbox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = ndk

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // Extract native libs to disk at install so the bundled chdman (shipped as
    // jniLibs/<abi>/libchdman.so) lands in the read-only nativeLibraryDir and
    // can be exec'd — Android blocks running binaries from writable app dirs.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    defaultConfig {
        applicationId = "name.rafaismy.retrotoolbox"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // "direct": the APK people install themselves; it updates itself from the
    // release page. "play": the Play Store bundle, which may not install
    // packages (src/play/AndroidManifest.xml drops that permission).
    flavorDimensions += "distribution"
    productFlavors {
        create("direct") { dimension = "distribution" }
        create("play") { dimension = "distribution" }
    }

    signingConfigs {
        create("release") {
            if (releaseSigning) {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigning) {
                println("[Gradle] Using RELEASE signing config for build.")
                signingConfigs.getByName("release")
            } else {
                println("[Gradle] Using DEBUG signing config for build.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Expo Launch runs a bare `flutter build appbundle --release`, which is Gradle's
// flavorless `bundleRelease`. Treat that as "the Play bundle": leave the direct
// flavor out, and mirror the result into bundle/release/, the only place the
// Flutter tool looks for an .aab when it was given no --flavor.
val bareBundle = gradle.startParameter.taskNames.any { it.substringAfterLast(':') == "bundleRelease" }
androidComponents {
    beforeVariants(selector().withFlavor("distribution", "direct")) { if (bareBundle) it.enable = false }
}
tasks.named { it == "bundlePlayRelease" }.configureEach {
    doLast {
        copy {
            from(layout.buildDirectory.dir("outputs/bundle/playRelease")) { include("*.aab") }
            into(layout.buildDirectory.dir("outputs/bundle/release"))
            rename { "app-release.aab" }
        }
    }
}

// The release workflow stages the Python app and its Android site-packages
// before `flutter build` (dart run serious_python:main package …, same
// requirements as there). A builder that only runs `flutter build` — Expo
// Launch — sets SERIOUS_PYTHON_APP and SERIOUS_PYTHON_SITE_PACKAGES but stages
// nothing, so do it from here, before serious_python_android packs those
// directories into the app.
val pythonAppDir = env["SERIOUS_PYTHON_APP"]
val stagePython = tasks.register<Exec>("stagePython") {
    onlyIf { pythonAppDir != null && !File(pythonAppDir, "main.py").exists() }
    val flutterSdk = Properties().apply {
        rootProject.file("local.properties").inputStream().use { load(it) }
    }.getProperty("flutter.sdk")
    workingDir = rootProject.projectDir.parentFile
    commandLine(
        "$flutterSdk/bin/dart", "run", "serious_python:main", "package", "python_app/", "-p", "Android",
        "-r", "zstandard", "-r", "pycryptodome", "-r", "retro-roster-patcher[images]>=0.8.0",
    )
}

rootProject.subprojects {
    if (name != "app") {
        // Plugins that compile native code without an ndkVersion of their own
        // (rar's libarchive build) would fall back to AGP's r27 default and ship
        // 4 KB-aligned libs. Give them the app's NDK.
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> { ndkVersion = ndk }
        }
    }
    if (name == "serious_python_android") {
        tasks.named { it == "packageApp" || it.startsWith("splitSitePackages_") || it.startsWith("copyOpt_") }
            .configureEach { dependsOn(stagePython) }
    }
}

flutter {
    source = "../.."
}
