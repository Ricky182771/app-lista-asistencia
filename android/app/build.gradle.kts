import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Llave de release: android/key.properties (ignorado por git; ver key.properties.example).
// Sin ese archivo (por ejemplo, en la compu de un compañero) el release se firma con la llave de
// depuración, para que `flutter run --release` siga funcionando; ese APK NO sirve para repartir.
val llaveRelease = Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) archivo.inputStream().use { load(it) }
}

android {
    namespace = "io.github.ricky182771.app_lista_asistencia"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.ricky182771.app_lista_asistencia"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (!llaveRelease.isEmpty) {
                storeFile = file(llaveRelease.getProperty("storeFile"))
                storePassword = llaveRelease.getProperty("storePassword")
                keyAlias = llaveRelease.getProperty("keyAlias")
                keyPassword = llaveRelease.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (llaveRelease.isEmpty) {
                logger.warn("android/key.properties no existe: el release se firma con la llave de depuración.")
                signingConfig = signingConfigs.getByName("debug")
            } else {
                signingConfig = signingConfigs.getByName("release")
            }
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
