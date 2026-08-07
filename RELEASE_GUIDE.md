# 📦 Phát Hành APK AegisNet

Hướng dẫn build APK đã ký và gửi tới người dùng, thủ công hoặc tự động qua
GitHub Actions.

Có hai kênh phân phối, dùng cùng lúc được:

| Kênh | Dùng khi |
|------|----------|
| **Firebase App Distribution** | Gửi cho nhóm tester qua email, họ được **báo tự động** khi có bản mới |
| **GitHub Releases** | Link tải công khai, làm bản lưu trữ theo từng phiên bản |

---

## 1. Tạo keystore — làm một lần duy nhất

Khoá này định danh app của bạn. Mọi bản cập nhật về sau **bắt buộc** phải ký
bằng đúng khoá này.

```bash
keytool -genkey -v -keystore android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

> [!CAUTION]
> **Mất file này là mất luôn khả năng cập nhật app.** Người dùng sẽ không cài đè
> được bản mới, và nếu đã lên Play thì không thể phát hành bản vá. Sao lưu
> `upload-keystore.jks` cùng mật khẩu ra nơi khác — trình quản lý mật khẩu, ổ
> cứng ngoài. Đừng chỉ để trên máy đang code.

Cả `*.jks` lẫn `key.properties` đều đã nằm trong `android/.gitignore`, nên chúng
sẽ không bị commit nhầm.

## 2. Cấu hình cho build local

Tạo `android/key.properties`:

```properties
storePassword=MẬT_KHẨU_KEYSTORE
keyPassword=MẬT_KHẨU_KHOÁ
keyAlias=upload
storeFile=upload-keystore.jks
```

Build và tự kiểm tra:

```bash
flutter build apk --release
```

Xác nhận đã ký đúng khoá — dòng in ra **không được** chứa `CN=Android Debug`:

```bash
APKSIGNER=$(ls "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
"$APKSIGNER" verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk | grep "certificate DN"
```

Xác nhận engine DNS có trong APK — phải ra **3**:

```bash
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -c libaegis_core.so
```

> [!IMPORTANT]
> Nếu ra 0, APK vẫn cài được nhưng **không lọc DNS gì cả** — app chạy ở chế độ
> fallback. Nguyên nhân gần như luôn là thiếu `cargo-ndk`. Cài bằng
> `cargo install cargo-ndk`. Gradle cố tình bỏ qua lỗi này để người không có
> Rust toolchain vẫn build được app, nên nó **không** làm build đỏ.

File APK nằm ở `build/app/outputs/flutter-apk/app-release.apk`, gửi thẳng cho
người dùng cài được.

## 3. Thiết lập GitHub Actions

Workflow `.github/workflows/release.yml` chạy khi bạn đẩy tag dạng `v*`.

### 3.1 Nạp secret cho việc ký

Chuyển keystore sang base64:

```bash
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks")) | Set-Clipboard

# macOS / Linux
base64 -w0 android/app/upload-keystore.jks | pbcopy
```

Vào **Settings → Secrets and variables → Actions → New repository secret**, tạo:

| Secret | Giá trị |
|--------|---------|
| `ANDROID_KEYSTORE_BASE64` | chuỗi base64 vừa tạo |
| `ANDROID_KEYSTORE_PASSWORD` | mật khẩu keystore |
| `ANDROID_KEY_PASSWORD` | mật khẩu khoá |
| `ANDROID_KEY_ALIAS` | `upload` |

### 3.2 Nạp secret cho Firebase

Bỏ qua phần này nếu chỉ dùng GitHub Releases — workflow tự bỏ qua bước Firebase
khi thiếu `FIREBASE_APP_ID`.

1. Tạo project ở [Firebase Console](https://console.firebase.google.com), thêm
   một **Android app** với package name `com.aegisnet.app`.
2. Lấy **App ID** ở *Project settings → General* (dạng `1:123...:android:abc...`).
3. Tạo service account: *Project settings → Service accounts → Generate new
   private key*, tải file JSON về.
4. Vào **App Distribution → Testers & Groups**, tạo group tên `testers` và thêm
   email người dùng. Tên group phải khớp với `groups: testers` trong workflow.

| Secret | Giá trị |
|--------|---------|
| `FIREBASE_APP_ID` | App ID ở bước 2 |
| `FIREBASE_SERVICE_ACCOUNT` | **toàn bộ nội dung** file JSON ở bước 3 |

## 4. Phát hành

Quy trình: làm việc trên `develop`, mở MR vào `main`. Merge là phát hành.

```
develop  ──MR──►  main
   │                │
   │                └─► phát hành thật: GitHub Release + mail cho tester
   └─► MR chỉ build kiểm tra, đính APK làm artifact để tải thử
```

### Khi mở MR từ `develop` vào `main`

Workflow build và kiểm tra, **không phát hành gì cả**. Vào tab Actions của lần
chạy đó, kéo xuống mục **Artifacts** để tải APK về cài thử. Artifact giữ 14 ngày.

### Khi merge MR vào `main`

1. Chạy `flutter analyze`, `flutter test`, `cargo test` — hỏng thì dừng
2. **Chặn nếu phiên bản đã được phát hành rồi** (quên tăng `version` trong
   `pubspec.yaml`). Bước này chạy trước khi build nên hỏng là biết ngay, không
   mất 7 phút chờ.
3. Build APK release đã ký. `versionName` lấy từ `pubspec.yaml`, `versionCode`
   lấy từ số thứ tự lần chạy workflow
4. **Chặn nếu APK thiếu engine Rust ở bất kỳ ABI nào trong 3**
5. **Chặn nếu APK bị ký bằng khoá debug**
6. Tạo GitHub Release kèm file APK
7. Đẩy lên Firebase App Distribution → tester nhận mail

> [!NOTE]
> Bước 6 đứng trước bước 7 là có chủ ý. GitHub Release chỉ phụ thuộc file đã
> build, còn Firebase phụ thuộc dịch vụ ngoài. Xếp ngược lại thì một trục trặc
> phía Firebase sẽ cuốn theo cả bản lưu trữ, dù APK hoàn toàn hợp lệ — đã xảy ra
> đúng một lần như vậy.

### Nhớ tăng version trước khi merge

Sửa `pubspec.yaml`:

```yaml
version: 1.0.1+1     # phần trước dấu + là thứ workflow dùng
```

Không tăng thì bước 2 chặn lại với thông báo rõ ràng, không âm thầm ghi đè bản
cũ.

### Phát hành lại bằng tay

Tab **Actions → 🚀 Release APK → Run workflow**, để trống ô version thì nó lấy
từ `pubspec.yaml`, hoặc nhập số khác để ghi đè.

> [!NOTE]
> Lần chạy đầu lâu (~15–20 phút) vì phải biên dịch `cargo-ndk` và tải Android
> NDK. Các lần sau nhanh hơn nhiều nhờ cache.

## 5. Người dùng cài như thế nào

**Qua Firebase:** họ nhận email mời, bấm link, cài app **App Tester** của
Firebase, rồi cài AegisNet từ trong đó. Bản mới về sau sẽ được báo tự động.

**Qua GitHub Release:** tải thẳng file `.apk`. Android sẽ hỏi cho phép "cài đặt
từ nguồn không xác định" — đây là chuyện bình thường với app ngoài Play Store.

> [!WARNING]
> AegisNet dùng `VpnService`, nên khi mở lần đầu Android sẽ hiện hộp thoại xin
> quyền VPN. Người dùng **phải bấm OK**, nếu bấm Cancel thì app hiện
> "UNPROTECTED" và không lọc gì. Nên nói trước điều này trong mail mời.

## 6. Đánh số phiên bản

`pubspec.yaml` đang để `version: 1.0.0+1`. Khi phát hành qua workflow, số này bị
ghi đè: `versionName` lấy từ tag, `versionCode` lấy từ số thứ tự lần chạy
workflow (luôn tăng, nên Android luôn coi bản mới là mới hơn).

Build local thì vẫn dùng số trong `pubspec.yaml`, nhớ tự tăng nếu cần cài đè.
