import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ————————————————— 发布签名配置 —————————————————
// 密钥不在仓库里，按以下顺序读取：
//   1. 环境变量（CI 用 GitHub Secrets 注入；本地也可临时设置）
//   2. android/keystore.properties（本地自用，已被 .gitignore 排除）
// 两者都没有时回退 debug 签名，保证任何环境都能构建出包（便于 PR / 贡献者）。
//   环境变量：GRKU_KEYSTORE_PATH / GRKU_KEYSTORE_PASSWORD / GRKU_KEY_ALIAS / GRKU_KEY_PASSWORD
val keystoreProps = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun signingValue(envKey: String, propKey: String): String? =
    System.getenv(envKey)?.takeIf { it.isNotBlank() }
        ?: keystoreProps.getProperty(propKey)?.takeIf { it.isNotBlank() }

val releaseStorePath = signingValue("GRKU_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("GRKU_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("GRKU_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("GRKU_KEY_PASSWORD", "keyPassword")
val hasReleaseKeystore = releaseStorePath != null &&
        File(releaseStorePath).exists() &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null

android {
    namespace = "com.example.github_releases_keep_update"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 等依赖要求开启 core library desugaring
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.github_releases_keep_update"
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
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = File(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                // minSdk 24 下 v2 签名为默认且必需（实测 v2=true）；
                // v1 是否生效由 AGP 按 minSdk 决定，这里显式声明以便将来降低 minSdk
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // 未提供密钥时（本地/PR）回退 debug 签名，避免构建失败
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
