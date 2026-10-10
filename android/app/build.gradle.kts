import java.io.File
import java.io.FileInputStream
import java.net.URI
import java.security.MessageDigest
import java.util.Properties
import java.util.zip.ZipInputStream

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

// The engine's source is a private submodule. A checkout without it has an
// empty rust/aegis_core, and the prebuilt engine below stands in.
val engineSourcePresent = file("../../rust/aegis_core/Cargo.toml").exists()

val buildRustEngine by tasks.registering(Exec::class) {
    val rustDir = file("../../rust/aegis_core")
    val jniLibs = file("src/main/jniLibs")
    workingDir = rustDir
    onlyIf { engineSourcePresent && isOnPath("cargo-ndk") }

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

// --- Prebuilt engine, for a checkout without the engine's source ---
// Every release carries aegis-engine-android.zip: the three libaegis_core.so
// of that release's APK. Without the source they are fetched into jniLibs, so
// a clone of this repository alone builds an app that filters DNS. The release
// of this checkout's own version is tried first and the latest one after it,
// because develop runs ahead of the last release.
//
//   -Paegis.prebuilt=false     build without an engine (fallback mode)
//   -Paegis.engineUrl=<url>    take the two files from another place
val engineAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

val fetchPrebuiltEngine by tasks.registering {
    val jniLibs = file("src/main/jniLibs")
    val pubspec = file("../../pubspec.yaml")
    val wanted = (findProperty("aegis.prebuilt") as String?) != "false"
    val customUrl = findProperty("aegis.engineUrl") as String?
    onlyIf {
        !engineSourcePresent && wanted &&
            engineAbis.any { !File(jniLibs, "$it/libaegis_core.so").exists() }
    }
    doLast {
        val releases = "https://github.com/vannt-dev/aegis-net/releases"
        val version = Regex("""^version:\s*([0-9]+(?:\.[0-9]+)*)""", RegexOption.MULTILINE)
            .find(pubspec.readText())?.groupValues?.get(1)
        val places = if (customUrl != null) {
            listOf(customUrl.trimEnd('/'))
        } else {
            listOfNotNull(version?.let { "$releases/download/v$it" }, "$releases/latest/download")
        }
        fun bytesOf(address: String): ByteArray =
            URI(address).toURL().openStream().use { it.readBytes() }

        for (place in places) {
            try {
                val zip = bytesOf("$place/aegis-engine-android.zip")
                val expected = String(bytesOf("$place/aegis-engine-android.zip.sha256"))
                    .trim().split(Regex("""\s+""")).first().lowercase()
                val actual = MessageDigest.getInstance("SHA-256").digest(zip)
                    .joinToString("") { "%02x".format(it) }
                check(actual == expected) { "checksum is $actual, expected $expected" }
                var written = 0
                ZipInputStream(zip.inputStream()).use { entries ->
                    while (true) {
                        val entry = entries.nextEntry ?: break
                        // Only what an engine archive holds; nothing may land
                        // outside jniLibs.
                        val abi = entry.name.substringBefore('/')
                        if (entry.name != "$abi/libaegis_core.so" || abi !in engineAbis) continue
                        File(jniLibs, entry.name).apply { parentFile.mkdirs() }.writeBytes(entries.readBytes())
                        written++
                    }
                }
                check(written == engineAbis.size) { "the archive holds $written of ${engineAbis.size} libraries" }
                println("[aegis] Prebuilt DNS engine from $place -> $jniLibs")
                return@doLast
            } catch (error: Exception) {
                println("[aegis] No prebuilt engine at $place: ${error.message}")
            }
        }
        println(
            "[aegis] WARNING: building without the DNS engine. The app installs and runs, " +
                "but in fallback mode it filters nothing.",
        )
    }
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(buildRustEngine)
    dependsOn(fetchPrebuiltEngine)
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
