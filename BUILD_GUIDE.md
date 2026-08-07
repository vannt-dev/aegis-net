# 🛠️ Hướng Dẫn Biên Dịch & Đóng Gói AegisNet (Build & Deployment Guide)

Tài liệu này hướng dẫn chi tiết cách thiết lập môi trường, biên dịch nhân **Rust Core Engine**, và đóng gói ứng dụng **AegisNet** ra các định dạng sản phẩm: **Android APK/AAB**, **iOS IPA**, và **Web Production Bundle**.

---

## 📋 Mục Lục
1. [Yêu Cầu Môi Trường (Prerequisites)](#1-yêu-cầu-môi-trường-prerequisites)
2. [Cấu Trúc Mã Nguồn](#2-cấu-trúc-mã-nguồn)
3. [Biên Dịch Nhân Rust Core Engine](#3-biên-dịch-nhân-rust-core-engine)
4. [Biên Dịch & Đóng Gói Android (APK / AAB)](#4-biên-dịch--đóng-gói-android-apk--aab)
5. [Biên Dịch & Đóng Gói iOS (IPA / TestFlight)](#5-biên-dịch--đóng-gói-ios-ipa--testflight)
6. [Biên Dịch & Đóng Gói Web Bundle](#6-biên-dịch--đóng-gói-web-bundle)
7. [Cấu Hình CI/CD Với GitHub Actions](#7-cấu-hình-cicd-với-github-actions)

---

## 1. Yêu Cầu Môi Trường (Prerequisites)

### Công cụ chung:
* **Flutter SDK**: v3.0.0 trở lên (Channel `stable`).
* **Rust Toolchain**: `rustup` & `cargo` (v1.75+).

### Biên dịch Android:
* **Android Studio** & **Android SDK** (API 24+).
* **Android NDK** (r25+).
* Target Rust Android ABIs:
  ```bash
  rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
  ```

### Biên dịch iOS:
* **macOS** chạy Xcode 15+.
* Target Rust iOS Architectures:
  ```bash
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
  ```

---

## 2. Cấu Trúc Mã Nguồn

```text
aegis-net/
├── rust/aegis_core/   # Mã nguồn Rust Engine (rule matcher, DNS Sinkhole, DoH, C-FFI)
├── android/           # Project Android Native (VpnService)
├── ios/               # Project iOS Native (NEPacketTunnelProvider)
├── lib/               # Mã nguồn Flutter (UI, Providers, Bridge)
└── web/               # File cấu hình Web
```

---

## 3. Biên Dịch Nhân Rust Core Engine

### Kiểm tra & Build thử nghiệm trên máy host:
```bash
cd rust/aegis_core
cargo check
cargo build --release
```

### Biên dịch ra thư viện Android (`.so`):

> **Đã tự động hoá trong Gradle.** Task `preBuild` trong
> `android/app/build.gradle.kts` tự chạy lệnh dưới đây mỗi khi có `cargo-ndk`
> trong `PATH`, nên `flutter build apk` / `flutter run` thông thường đã sinh sẵn
> `.so`. Chỉ chạy tay khi muốn build trước hoặc debug. Nếu thiếu toolchain Rust,
> task được bỏ qua và app chạy ở chế độ fallback thuần Dart (không crash).

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install cargo-ndk
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ../../android/app/src/main/jniLibs build --release
```

---

## 4. Biên Dịch & Đóng Gói Android (APK / AAB)

1. Tải các gói phụ thuộc Flutter:
   ```bash
   flutter pub get
   ```

2. Biên dịch file APK cài đặt trực tiếp:
   ```bash
   flutter build apk --release --split-per-abi
   ```
   * *File đầu ra*: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

3. Biên dịch file Android App Bundle (AAB) để đăng Play Store:
   ```bash
   flutter build appbundle --release
   ```
   * *File đầu ra*: `build/app/outputs/bundle/release/app-release.aab`

---

## 5. Biên Dịch & Đóng Gói iOS (IPA / TestFlight)

> **⚠️ iOS đang trong quá trình hoàn thiện.** Entitlement `networkextension`,
> App Group, `VpnManager.swift` (MethodChannel → `NETunnelProviderManager`) và
> cơ chế chia sẻ state giữa app với extension đều đã có. Còn thiếu: **target
> Network Extension** (`PacketTunnel`) chưa được tạo trong project, và
> `AegisCore.xcframework` chưa được link. Nên lọc DNS toàn hệ thống **chưa chạy**
> — các bước dưới chỉ build phần vỏ Flutter. Xem
> [`ios/IOS_SETUP.md`](ios/IOS_SETUP.md) cho phần còn lại.

> **Không dùng CocoaPods.** Repo không có `Podfile`; plugin native duy nhất
> (`shared_preferences_foundation`) đi qua Swift Package Manager. Chạy
> `pod install` sẽ báo *No Podfile found*. Khi mở Xcode, mở
> `ios/Runner.xcworkspace` — **không** phải `Runner.xcodeproj`, vì mở thẳng
> project thì Xcode không resolve được package sinh ra trong
> `ios/Flutter/ephemeral/` và báo *Missing package product
> 'FlutterGeneratedPluginSwiftPackage'*.

1. Tải phụ thuộc (tự sinh luôn Swift package cho iOS):
   ```bash
   flutter pub get
   ```

2. Build phần vỏ để kiểm tra biên dịch (không cần tài khoản Apple):
   ```bash
   flutter build ios --no-codesign
   ```
   * *File đầu ra*: `build/ios/iphoneos/Runner.app`

3. Đóng gói IPA — chỉ làm được sau khi đã tạo target `PacketTunnel` và chọn
   Team trong Xcode:
   ```bash
   flutter build ipa --release
   ```
   * *File đầu ra*: `build/ios/archive/Runner.xcarchive`
   * Thiếu team hoặc thiếu extension thì bước này fail ở khâu provisioning, vì
     app khai entitlement `networkextension` mà không kèm extension nào.

---

## 6. Biên Dịch & Đóng Gói Web Bundle

1. Biên dịch trang Web tĩnh dạng Production:
   ```bash
   flutter build web --release
   ```
   * *File đầu ra*: Thư mục `build/web/`

2. Khởi chạy thử nghiệm local bằng Node/NPX:
   ```bash
   npx serve build/web -l 8080
   ```

---

## 7. Cấu Hình CI/CD Với GitHub Actions

Dự án đã được cấu hình file `.github/workflows/build.yml` tự động kiểm tra và build khi đẩy code lên nhánh `main`:
* Tự động lướt qua các bước kiểm tra cú pháp Rust và Flutter.
* Tự động đóng gói bản Web và Android APK trên môi trường Cloud Ubuntu Runner.
