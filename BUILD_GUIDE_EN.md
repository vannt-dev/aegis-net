# 🛠️ AegisNet Build & Deployment Guide

This document provides detailed instructions for setting up the environment, compiling the **Rust Core Engine**, and building **AegisNet** across **Android (APK/AAB)**, **iOS (IPA)**, and **Web Production Bundles**.

---

## 📋 Table of Contents
1. [Prerequisites](#1-prerequisites)
2. [Source Code Structure](#2-source-code-structure)
3. [Building Rust Core Engine](#3-building-rust-core-engine)
4. [Building & Packaging Android (APK / AAB)](#4-building--packaging-android-apk--aab)
5. [Building & Packaging iOS (IPA / TestFlight)](#5-building--packaging-ios-ipa--testflight)
6. [Building & Serving Web Bundle](#6-building--serving-web-bundle)
7. [Automated CI/CD with GitHub Actions](#7-automated-cicd-with-github-actions)

---

## 1. Prerequisites

### Common Tools:
* **Flutter SDK**: v3.0.0 or higher (`stable` channel).
* **Rust Toolchain**: `rustup` & `cargo` (v1.75+).

### Android Builds:
* **Android Studio** & **Android SDK** (API 24+).
* **Android NDK** (r25+).
* Target Rust Android ABIs:
  ```bash
  rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
  ```

### iOS Builds:
* **macOS** running Xcode 15+.
* Target Rust iOS Architectures:
  ```bash
  rustup target add aarch64-apple-ios x86_64-apple-ios-simulator
  ```

---

## 2. Source Code Structure

```text
aegis-net/
├── rust/aegis_core/   # Rust Core Engine (Trie, DNS Sinkhole, C-FFI exports)
├── android/           # Native Android Project (VpnService)
├── ios/               # Native iOS Project (NEPacketTunnelProvider)
├── lib/               # Flutter Application (UI, Providers, Bridge)
└── web/               # Web configuration assets
```

---

## 3. Building Rust Core Engine

### Test & Compile locally on Host machine:
```bash
cd rust/aegis_core
cargo check
cargo build --release
```

### Cross-compile to Android shared libraries (`.so`):
```bash
cargo install cargo-ndk
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ../../android/app/src/main/jniLibs build --release
```

---

## 4. Building & Packaging Android (APK / AAB)

1. Fetch Flutter dependencies:
   ```bash
   flutter pub get
   ```

2. Build split-per-ABI APKs:
   ```bash
   flutter build apk --release --split-per-abi
   ```
   * *Output file*: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

3. Build Android App Bundle (AAB) for Google Play Store:
   ```bash
   flutter build appbundle --release
   ```
   * *Output file*: `build/app/outputs/bundle/release/app-release.aab`

---

## 5. Building & Packaging iOS (IPA / TestFlight)

1. Install Cocoapods:
   ```bash
   cd ios && pod install && cd ..
   ```

2. Build iOS IPA bundle:
   ```bash
   flutter build ipa --release
   ```
   * *Output file*: `build/ios/archive/Runner.xcarchive`

---

## 6. Building & Serving Web Bundle

1. Build production static Web bundle:
   ```bash
   flutter build web --release
   ```
   * *Output directory*: `build/web/`

2. Serve locally using Node/NPX:
   ```bash
   npx serve build/web -l 8080
   ```

---

## 7. Automated CI/CD with GitHub Actions

The repository includes `.github/workflows/build.yml` which automatically runs syntax checks, Rust builds, and Flutter Web/Android APK builds on every push to `main`.
