import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

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
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["password"] as String
                storeFile = keystoreProperties["storeFile"]?.let { rootProject.file(it) }
                storePassword = keystoreProperties["password"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                println("[Gradle] Using RELEASE signing config for build.")
                signingConfigs.getByName("release")
            } else {
                println("[Gradle] Using DEBUG signing config for build.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Plugins that compile native code without an ndkVersion of their own (rar's
// libarchive build) would fall back to AGP's r27 default and ship 4 KB-aligned
// libs. Give them the app's NDK.
rootProject.subprojects {
    if (name != "app") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> { ndkVersion = ndk }
        }
    }
}

flutter {
    source = "../.."
}
