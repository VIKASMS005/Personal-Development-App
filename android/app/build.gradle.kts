plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle plugin (keep for Flutter builds)
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Use your app's package namespace
    namespace = "com.example.flutter_application_1"

    // Set concrete SDK ints to avoid Kotlin-DSL lookup issues
    // Use values compatible with your Flutter + plugins:
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.flutter_application_1"
        // Minimum SDK — set to 23 if a plugin requires it, otherwise 21 is typical.
        // I set 23 (you can change to 21 if you prefer).
        minSdk = flutter.minSdkVersion
        targetSdk = 36

        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11

        // Enable core library desugaring (Kotlin DSL property name)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        // Keep jvmTarget consistent with Java version above
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        // The project currently has no production keystore. Use the standard
        // local debug key so locally built release APKs are installable.
        create("localRelease") {
            val debugKeystore = file(System.getProperty("user.home") + "/.android/debug.keystore")
            if (debugKeystore.exists()) {
                storeFile = debugKeystore
                storePassword = "android"
                keyAlias = "AndroidDebugKey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("localRelease")
        }
    }
}

dependencies {
    // Core AndroidX
    implementation("androidx.core:core:1.13.1")
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // Desugaring library (version 2.1.4 or newer as required)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    

    // If you have other module-level dependencies, add them here, e.g.:
    // implementation("com.google.firebase:firebase-analytics:21.1.0")
}
