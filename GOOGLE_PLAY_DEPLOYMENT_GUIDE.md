# 🚀 Google Play Store Deployment Guide for AegisNet

Hướng dẫn chi tiết từng bước đưa ứng dụng **AegisNet** lên **Google Play Store** (Dành cho Android).

---

## 📋 Mục Lục
1. [Điều Kiện Cần Chuẩn Bị](#1-điều-kiện-cần-chuẩn-bị)
2. [Tạo Keystore & Cấu Hình Ký Tên (App Signing)](#2-tạo-keystore--cấu-hình-ký-tên-app-signing)
3. [Tối Ưu Mã Nguồn & Biên Dịch Bản App Bundle (.aab)](#3-tối-ưu-mã-nguồn--biên-dịch-bản-app-bundle-aab)
4. [Chính Sách Bắt Buộc Của Google Cho VpnService](#4-chính-sách-bắt-buộc-của-google-cho-vpnservice)
5. [Tạo App & Khai Báo Thông Tin Trên Google Play Console](#5-tạo-app--khai-báo-thông-tin-trên-google-play-console)
6. [Tải Bản Build Up Lên & Gửi Duyệt](#6-tải-bản-build-up-lên--gửi-duyệt)

---

## 1. Điều Kiện Cần Chuẩn Bị
* **Tài khoản Google Play Console**: Đã đăng ký và thanh toán phí một lần ($25 USD).
* **Flutter SDK**: Bản `stable` mới nhất.
* **Android Studio & NDK**: Đã cài đặt để biên dịch thư viện Rust `.so`.

---

## 2. Tạo Keystore & Cấu Hình Ký Tên (App Signing)

### Bước 2.1: Tạo Android Release Keystore
Mở terminal tại thư mục dự án và chạy lệnh sau (thay thế mật khẩu của bạn):

```bash
keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

> [!CAUTION]
> **RẤT QUAN TRỌNG**: Hãy sao lưu file `upload-keystore.jks` và lưu lại mật khẩu ở nơi an toàn. Nếu mất file này, bạn sẽ KHÔNG THỂ cập nhật ứng dụng trên Google Play trong tương lai!

### Bước 2.2: Tạo File `android/key.properties`
Tạo một file mới tại vị trí `android/key.properties` với nội dung:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
```

### Bước 2.3: Cấu hình `android/app/build.gradle.kts`
Cập nhật khối `signingConfigs` trong file `android/app/build.gradle.kts`:

```kotlin
import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    ...
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
```

---

## 3. Tối Ưu Mã Nguồn & Biên Dịch Bản App Bundle (.aab)

### Bước 3.1: Biên dịch thư viện Rust Core cho các kiến trúc Android
```bash
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install cargo-ndk
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o android/app/src/main/jniLibs build --manifest-path rust/aegis_core/Cargo.toml --release
```

### Bước 3.2: Biên dịch Android App Bundle (.aab)
```bash
flutter clean
flutter pub get
flutter build appbundle --release
```
* **File kết quả**: `build/app/outputs/bundle/release/app-release.aab`

---

## 4. Chính Sách Bắt Buộc Của Google Cho VpnService

Ứng dụng AegisNet sử dụng quyền `android.permission.BIND_VPN_SERVICE`. Google có quy định RẤT NGHIÊM NGẠỢT:

1. **Tuyên bố tính năng cốt lõi (Core Functionality Declaration)**:
   * Trong Google Play Console, bạn phải chọn lý do dùng `VpnService` là: **"Bảo vệ riêng tư & lọc nội dung theo yêu cầu người dùng (Security / Local Content Filter)"**.
2. **Video demo tính năng (Proof Video)**:
   * Google yêu cầu 1 link YouTube video (unlisted) quay lại cảnh người dùng bật/tắt công tắc bảo vệ trên app và thấy quảng cáo bị chặn thực tế.

---

## 5. Tạo App & Khai Báo Thông Tin Trên Google Play Console

1. Truy cập [Google Play Console](https://play.google.com/console).
2. Bấm **Create App**:
   * App name: **AegisNet - Privacy & Ad Guard**
   * Default language: **English** hoặc **Vietnamese**
   * App or game: **App**
   * Free or paid: **Free**
3. Hoàn thành các mục **App Setup**:
   * **Privacy Policy URL**: Dẫn tới đường link chính sách bảo mật (Ví dụ: `https://vannt-dev.github.io/aegis-net/privacy.html`).
   * **App Access**: Chọn "All functionality is available without special access restrictions".
   * **Ads**: Chọn "No, my app does not contain ads".
   * **Content Ratings**: Hoàn thành bản khảo sát độ tuổi (chọn 3+ hoặc Everyone).
   * **Target Audience**: Chọn 13+.
   * **Data Safety**: Khai báo rằng ứng dụng **KHÔNG thu thập hay chia sẻ dữ liệu cá nhân lên máy chủ bên ngoài** (Zero-Data Collection).

---

## 6. Tải Bản Build Up Lên & Gửi Duyệt

1. Vào mục **Testing** -> **Internal testing** (Thử nghiệm nội bộ) hoặc **Production** (Chính thức).
2. Tạo **New Release**.
3. Kéo thả file `app-release.aab` vừa build ở Bước 3.2 vào ô tải lên.
4. Điền **Release Notes** (Ghi chú phiên bản):
   ```text
   - Initial release of AegisNet Privacy Guard.
   - High-speed Rust Core Engine DNS Ad-blocking.
   - SafeSearch enforcement & Multi-language support.
   ```
5. Bấm **Save** -> **Review Release** -> **Start rollout to Production**.
6. Thời gian Google xét duyệt thường từ **1 - 3 ngày**. Sau khi duyệt, ứng dụng sẽ có mặt trên Google Play Store!
