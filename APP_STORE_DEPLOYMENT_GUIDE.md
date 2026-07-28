# 🍎 Apple App Store Deployment Guide for AegisNet

Hướng dẫn chi tiết từng bước đưa ứng dụng **AegisNet** lên **Apple App Store** (Dành cho iOS & iPadOS).

---

## 📋 Mục Lục
1. [Điều Kiện Cần Chuẩn Bị](#1-điều-kiện-cần-chuẩn-bị)
2. [Xin Quyền Network Extension Entitlement Từ Apple](#2-xin-quyền-network-extension-entitlement-từ-apple)
3. [Cấu Hình App ID & Provisioning Profile Trên Apple Developer Portal](#3-cấu-hình-app-id--provisioning-profile-trên-apple-developer-portal)
4. [Cấu Hình Dự Án Trên Xcode](#4-cấu-hình-dự-án-trên-xcode)
5. [Biên Dịch Thư Viện Rust & Khởi Tạo Bản Build IPA](#5-biên-dịch-thư-viện-rust--khởi-tạo-bản-build-ipa)
6. [Tải Lên TestFlight & Gửi Duyệt Trên App Store Connect](#6-tải-lên-testflight--gửi-duyệt-trên-app-store-connect)

---

## 1. Điều Kiện Cần Chuẩn Bị
* **Máy tính macOS**: Đã cài đặt phiên bản **Xcode 15+**.
* **Tài khoản Apple Developer Program**: ($99 USD / năm).
* **Thiết bị iPhone/iPad thật**: Đã bật Developer Mode để test ứng dụng.

---

## 2. Xin Quyền Network Extension Entitlement Từ Apple

Ứng dụng AegisNet hoạt động theo cơ chế **NEPacketTunnelProvider** (Network Extension VPN). Apple yêu cầu bạn phải xin phê duyệt quyền này trước:

1. Truy cập trang yêu cầu của Apple: [Apple Network Extension Form](https://developer.apple.com/contact/request/network-extension/).
2. Điền thông tin:
   * **App Name**: AegisNet
   * **Bundle Identifier**: `com.aegisnet.app`
   * **Entitlement requested**: `Packet Tunnel Provider (NEPacketTunnelProvider)`
   * **Brief Description**: *"AegisNet is a privacy-focused local DNS filtering app that runs a local sinkhole on the device to block malware, trackers, and user-selected ad domains without routing traffic to external servers."*
3. Apple thường sẽ gửi email chấp thuận trong vòng **24 - 48 giờ**.

---

## 3. Cấu Hình App ID & Provisioning Profile Trên Apple Developer Portal

1. Truy cập [Apple Developer Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
2. **Tạo App ID mới**:
   * Platform: **iOS**
   * Description: **AegisNet Main App**
   * Bundle ID: **Explicit** -> `com.aegisnet.app`
   * Capabilities: Tích chọn **Network Extensions** và **Personal VPN**.
3. **Tạo App Extension ID (Cho PacketTunnelProvider)**:
   * Description: **AegisNet Tunnel Extension**
   * Bundle ID: **Explicit** -> `com.aegisnet.app.PacketTunnel`
   * Capabilities: Tích chọn **Network Extensions**.
4. **Tạo Provisioning Profiles**:
   * Tạo 2 App Store Provisioning Profiles riêng biệt cho cả Main App (`com.aegisnet.app`) và Extension (`com.aegisnet.app.PacketTunnel`).

---

## 4. Cấu Hình Dự Án Trên Xcode

1. Mở dự án trong Xcode bằng lệnh:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. Cấu hình **Signing & Capabilities** cho Target `Runner`:
   * Team: Chọn tài khoản Apple Developer của bạn.
   * Bundle Identifier: `com.aegisnet.app`
   * Bấm `+ Capability` -> Chọn **Network Extensions** -> Tích chọn **Packet Tunnel**.
3. Tạo file `ios/Runner/Runner.entitlements`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
   	<key>com.apple.developer.networking.networkextension</key>
   	<array>
   		<string>packet-tunnel-provider</string>
   	</array>
   </dict>
   </plist>
   ```

---

## 5. Biên Dịch Thư Viện Rust & Khởi Tạo Bản Build IPA

### Bước 5.1: Biên dịch thư viện tĩnh Rust (.a) cho iOS
```bash
rustup target add aarch64-apple-ios x86_64-apple-ios-simulator
cargo build --manifest-path rust/aegis_core/Cargo.toml --target aarch64-apple-ios --release
```

### Bước 5.2: Tạo gói lưu trữ Archive / IPA
```bash
flutter clean
flutter pub get
flutter build ipa --release
```
* **File kết quả**: `build/ios/archive/Runner.xcarchive`

---

## 6. Tải Lên TestFlight & Gửi Duyệt Trên App Store Connect

### Bước 6.1: Tải bản build lên bằng Xcode Transporter
1. Mở phần mềm **Xcode** -> Chọn menu **Product** -> **Archive**.
2. Chọn bản Archive vừa tạo và bấm **Distribute App**.
3. Chọn phương thức **App Store Connect** -> **Upload** -> Bấm **Submit**.

### Bước 6.2: Cấu hình App trên App Store Connect
1. Truy cập [App Store Connect](https://appstoreconnect.apple.com/).
2. Bấm dấu `+` để tạo **New App**:
   * Name: **AegisNet - Privacy Guard**
   * Primary Language: **English** hoặc **Vietnamese**
   * Bundle ID: `com.aegisnet.app`
   * SKU: `aegis-net-001`
3. Hoàn thành trang thông tin ứng dụng:
   * **Screenshots**: Tải lên hình ảnh giao diện app trên màn hình 6.7" iPhone và 12.9" iPad.
   * **Description**: Mô tả các tính năng nổi bật (Chặn quảng cáo, DNS Cache siêu tốc, SafeSearch, Đa ngôn ngữ).
   * **App Privacy**: Khai báo rằng ứng dụng KHÔNG thu thập bất kỳ dữ liệu nào (Data Not Collected).
4. **App Review Information (Ghi chú cho Đội ngũ Kiểm duyệt Apple)**:
   * Cung cấp ghi chú hướng dẫn: *"This app utilizes a local DNS sinkhole via NEPacketTunnelProvider to block adware and malware locally on the device without routing any traffic outside. Please tap the central power button to activate protection."*
5. Chọn bản build đã tải lên từ **TestFlight** -> Bấm **Submit for Review**.
6. Thời gian duyệt của Apple thường từ **24 - 48 giờ**.
