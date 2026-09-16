import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials live in android/key.properties, which is untracked
// (see android/.gitignore) so the upload keystore's passwords never get committed.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.libsk.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion


    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // Must match the package_name in android/app/google-services.json and the
        // App ID registered with Firebase/FCM, or push + App Check won't route.
        applicationId = "com.libsk.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Values come from key.properties (loaded above). If that file is
            // absent, storeFile stays null and a release build FAILS LOUDLY rather
            // than silently falling back to the debug key (the bug Play flagged).
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // Sign release builds with the real upload keystore, not debug.
            signingConfig = signingConfigs.getByName("release")
            // NOTE: R8 minify + resource shrinking are enabled automatically by the
            // Flutter Gradle plugin for release builds, and it also auto-includes
            // this module's proguard-rules.pro (see FlutterPlugin.kt). No explicit
            // isMinifyEnabled/proguardFiles wiring is needed here.
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // NormalTheme (values/styles.xml + values-night/styles.xml) uses a
    // Theme.MaterialComponents parent, which requires the Material Components
    // library on the classpath. The app module otherwise declares no deps.
    implementation("com.google.android.material:material:1.12.0")
}
