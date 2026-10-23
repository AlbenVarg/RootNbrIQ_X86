plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.nbriq.wear.watchface"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.nbriq.wear.watchface"
        // NBRiq / shasta: Wear OS 2.0, Android 7.1.1 (API 25), x86.
        minSdk = 25
        targetSdk = 25
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            // sin sufijo para poder reinstalar con `adb install -r` sin renombrar
            applicationIdSuffix = ""
            versionNameSuffix = ""
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    packaging {
        resources {
            excludes += setOf("/META-INF/{AL2.0,LGPL2.1}")
        }
    }
}

dependencies {
    // API clásica de esferas (CanvasWatchFaceService) y complicaciones para Wear OS 2.0.
    // 2.9.0 es la última versión que conserva android.support.wearable.watchface.*;
    // ya depende solo de AndroidX, así que no hace falta Jetifier.
    implementation("com.google.android.support:wearable:2.9.0")
}
