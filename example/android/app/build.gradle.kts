import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val rustAndroidAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
val rustProjectDir = rootProject.projectDir.resolve("../../native/rust/net_engine")
val rustOutputDir = layout.buildDirectory.dir("generated/rustJniLibs")
val rustBuildProfile = providers.gradleProperty("rustProfile")
    .map { it.trim().lowercase() }
    .orElse("release")

android {
    namespace = "com.example.example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.addAll(rustAndroidAbis)
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets.getByName("main").jniLibs.srcDir(rustOutputDir)
}

flutter {
    source = "../.."
}

val buildRustAndroidLibs by tasks.registering {
    group = "rust"
    description = "Build net_engine Rust shared libraries for Android ABIs"

    inputs.files(
        fileTree(rustProjectDir.resolve("src")) { include("**/*.rs") },
        rustProjectDir.resolve("Cargo.toml"),
        rustProjectDir.resolve("Cargo.lock"),
    )
    outputs.dir(rustOutputDir)

    doLast {
        val profile = rustBuildProfile.get()
        if (profile != "debug" && profile != "release") {
            throw GradleException("Invalid rustProfile=$profile. Use debug or release.")
        }

        val outputDir = rustOutputDir.get().asFile
        if (outputDir.exists()) {
            outputDir.deleteRecursively()
        }
        outputDir.mkdirs()

        val cargoArgs = mutableListOf(
            "ndk",
            "-o",
            outputDir.absolutePath,
            "--platform",
            flutter.minSdkVersion.toString(),
        )
        rustAndroidAbis.forEach { abi ->
            cargoArgs.add("-t")
            cargoArgs.add(abi)
        }
        cargoArgs.add("build")
        if (profile == "release") {
            cargoArgs.add("--release")
        }

        val result = exec {
            workingDir = rustProjectDir
            commandLine("cargo", *cargoArgs.toTypedArray())
            isIgnoreExitValue = true
        }

        if (result.exitValue != 0) {
            throw GradleException(
                "Rust Android build failed. Install cargo-ndk (`cargo install cargo-ndk`) " +
                    "and ensure Android NDK is available.",
            )
        }
    }
}

tasks.named("preBuild") {
    dependsOn(buildRustAndroidLibs)
}
