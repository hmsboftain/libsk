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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
