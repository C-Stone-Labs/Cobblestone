import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cobblestone.cobblestone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.cobblestone.cobblestone"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            val keystoreProperties = Properties()
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    lint {
        // Release build'de lint analizi (yalnızca statik uyarıdır)
        // RAM kısıtlı ortamlarda aşamayı çökertebiliyor; APK üretimini engelleme.
        checkReleaseBuilds = false
        abortOnError = false
    }

    buildTypes {
        release {
            // v5.1.1: key.properties yoksa sessizce DEBUG imzaya düşmek yerine
            // derlemeyi durdur (Play'e yanlış imzalı AAB gitmesi imkânsızlaştı).
            // Geliştirme makinesinde bilerek debug imza istenirse:
            //   cd android && ./gradlew assembleRelease -PdebugSigning
            val kp = rootProject.file("key.properties")
            val allowDebugSigning = project.hasProperty("debugSigning") ||
                (project.findProperty("allowDebugSigning")?.toString() == "true")
            signingConfig = when {
                kp.exists() -> signingConfigs.getByName("release")
                allowDebugSigning -> {
                    logger.warn("UYARI: key.properties yok — APK/AAB DEBUG imzalı olacak. Play'e yükleme!")
                    signingConfigs.getByName("debug")
                }
                else -> throw GradleException(
                    "android/key.properties bulunamadı. Play Store imzasız (debug) AAB üretimi " +
                        "engellendi. Kendi keystore'unu yerleştir ya da bilerek debug imza için " +
                        "--debug-signing bayrağını kullan."
                )
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Yerli Media3 çalma servisi (PlaybackService, EqEngine, Rhythm)
    implementation("androidx.media3:media3-common:1.9.4")
    implementation("androidx.media3:media3-exoplayer:1.9.4")
    implementation("androidx.media3:media3-session:1.9.4")
}
