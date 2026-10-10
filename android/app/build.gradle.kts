plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// 发布签名
//
// 若存在 android/key.properties，则用它指定的密钥签名（CI 里是自签密钥）；
// 否则回退到 debug 密钥，保证本地 `flutter run --release` / `flutter build apk`
// 在没有密钥的机器上依然可用。
//
// key.properties 示例（不要提交到仓库，已在 .gitignore 中忽略）：
//   storeType=PKCS12          （可选，默认 PKCS12）
//   storePassword=...
//   keyPassword=...
//   keyAlias=cmsplayer
//   storeFile=/abs/path/to/release.p12
//
// storeType 默认取 PKCS12：JDK 9 起 keytool 与 openssl 的默认输出都是 PKCS12，
// 显式写死可以彻底摆脱"AGP 到底按什么格式读"的猜测。手上有真正的 JKS 时改成 JKS。
// ---------------------------------------------------------------------------
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.cmsplayer.cms_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.cmsplayer.cms_player"
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
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeType = keystoreProperties.getProperty("storeType", "PKCS12")
                keyAlias = keystoreProperties.getProperty("keyAlias", "")
                keyPassword = keystoreProperties.getProperty("keyPassword", "")
                storePassword = keystoreProperties.getProperty("storePassword", "")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { storePath ->
                    rootProject.file(storePath)
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
