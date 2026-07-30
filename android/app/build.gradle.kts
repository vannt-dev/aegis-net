import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. android/key.properties is gitignored and holds the keystore
// password, so a checkout without it still builds — it just falls back to the
// debug key, which is fine for local runs but must never be distributed.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.aegisnet.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aegisnet.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Debug keys differ per machine, so an APK signed this way cannot
                // be installed over one built elsewhere. Loud on purpose.
                logger.warn(
                    "[aegis] android/key.properties missing — signing release with the DEBUG key. " +
                        "Do NOT distribute this APK.",
                )
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

// --- Rust DNS engine (libaegis_core.so) ---
// Builds the native engine with cargo-ndk into jniLibs before the APK is
// assembled. Best-effort: if the Rust toolchain / cargo-ndk / NDK is not
// available the task is skipped and the app runs in graceful fallback
// (AegisVpnService.nativeAvailable == false) instead of failing the build.
val isWindows = System.getProperty("os.name").startsWith("Windows", ignoreCase = true)

fun isOnPath(exe: String): Boolean {
    val exts = if (isWindows) listOf(".exe", ".bat", ".cmd", "") else listOf("")
    return System.getenv("PATH")?.split(File.pathSeparator)?.any { dir ->
        exts.any { ext -> File(dir, exe + ext).canExecute() }
    } ?: false
}

val buildRustEngine by tasks.registering(Exec::class) {
    val rustDir = file("../../rust/aegis_core")
    val jniLibs = file("src/main/jniLibs")
    workingDir = rustDir
    onlyIf { rustDir.exists() && isOnPath("cargo-ndk") }

    val cargoArgs = listOf(
        "ndk", "-t", "arm64-v8a", "-t", "armeabi-v7a", "-t", "x86_64",
        "-o", jniLibs.absolutePath, "build", "--release",
    )
    commandLine(if (isWindows) listOf("cmd", "/c", "cargo") + cargoArgs else listOf("cargo") + cargoArgs)
    isIgnoreExitValue = true

    doFirst {
        environment("ANDROID_NDK_HOME", android.ndkDirectory.absolutePath)
        println("[aegis] Building Rust DNS engine via cargo-ndk -> $jniLibs")
    }
}

tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(buildRustEngine) }

dependencies {}
