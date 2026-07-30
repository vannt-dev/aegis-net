# Thiết Kế Icon Ứng Dụng AegisNet

**Ngày:** 2026-07-30
**Trạng thái:** Đã duyệt, chờ lập kế hoạch triển khai

## 1. Vấn đề

Android, iOS và web build của AegisNet vẫn đang dùng icon Flutter mặc định. Khi
người dùng cài app, biểu tượng trên home screen không hề liên quan đến sản phẩm.
Cụ thể những chỗ còn logo mặc định:

- `android/app/src/main/res/mipmap-*/ic_launcher.png` (5 mật độ)
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (15 file PNG)
- `web/favicon.png`, `web/icons/Icon-*.png`
- `web/manifest.json` — còn `"name": "aegis_net"`, mô tả `"A new Flutter
  project."`, màu `#0175C2` của Flutter

Android hiện cũng chưa có adaptive icon (`mipmap-anydpi-v26/`), nghĩa là trên
Android 8+ hệ thống phải tự bọc icon legacy vào một nền trắng.

## 2. Mục tiêu

Thay toàn bộ icon mặc định bằng một icon nhận diện được của AegisNet, phủ đủ
Android (kể cả adaptive + themed icon), iOS và web.

**Ngoài phạm vi:** splash screen / launch screen. `launch_background.xml` của
Android và `LaunchImage.imageset` của iOS giữ nguyên trong lần làm này.

## 3. Thiết kế artwork

### 3.1 Ý tưởng

Hình khiên (Aegis là tên chiếc khiên trong thần thoại Hy Lạp) với đồ hình node
mạng khắc bên trong — truyền đạt đồng thời "bảo vệ" và "DNS/mạng".

### 3.2 Hình học

Mô tả trên canvas 1024×1024:

- **Khiên**: cạnh trên hơi cong lên, hai vai bo tròn, hai cạnh dưới hội tụ về
  một mũi tù. Đường path cao **542px (53% canvas)** (đỉnh `y=222`, mũi `y=764`),
  bề ngang lớn nhất **396px (39% canvas)** (`x` từ 314 đến 710). Tâm path ở
  `y=493`, tức lệch **lên trên 19px (~2%)** so với tâm canvas — khiên là hình
  nặng ở đáy, canh giữa toán học sẽ trông bị tụt.
- **Nét viền khiên**: dày 34px, `stroke-linejoin="round"`.
- **Mạch bên trong**: đúng 4 node — 1 node trung tâm bán kính 46px, 3 node vệ
  tinh bán kính 30px tại đỉnh của tam giác đều xoay 90°. Nối bằng 3 đoạn thẳng
  nét 20px.

Giới hạn 4 node là có chủ đích: ở kích thước hiển thị 48px, mỗi node chỉ còn
khoảng 1.4px. Thêm chi tiết nữa sẽ nhoè thành vệt.

### 3.3 Màu

| Thành phần | Giá trị |
|---|---|
| Nền | radial gradient `#111B22` (giữa) → `#0A0F14` (rìa) |
| Viền khiên | `#18FFFF` + outer glow (Gaussian blur 18px, opacity 45%) |
| Đường mạch | `#18FFFF` @ 55% opacity |
| Node | `#18FFFF` đặc; node trung tâm thêm halo cyan mờ |
| Lòng khiên | `#18FFFF` @ 7% |

`#18FFFF` là `Colors.cyanAccent`, màu accent của theme mặc định Neon Cyan trong
`lib/src/providers/theme_provider.dart`. Lớp nhuộm 7% ở lòng khiên để hình khiên
vẫn đọc ra được thành một khối kín khi thu nhỏ, thay vì chỉ là đường viền rỗng.

### 3.4 Safe zone

Android adaptive icon chỉ đảm bảo hiển thị vòng tròn đường kính 66/108 ở giữa
canvas — tức bán kính **312px** trên canvas 1024, tâm tại (512, 512).
**Toàn bộ khiên và mạch phải nằm gọn trong vòng tròn này.** Riêng glow được phép
tràn ra ngoài — mất phần glow ở rìa không ảnh hưởng nhận diện.

Điểm dễ sai: nét viền dày 34px **nằm giữa** đường path, nên hình thật lan ra
thêm **17px** ra ngoài path. Ràng buộc phải áp lên bao ngoài của nét viền, không
phải lên path.

Điểm xa tâm nhất **không phải** mũi đáy, giữa cạnh trên hay vai, mà là **góc nối
giữa cạnh trên và vai** — nằm chéo so với tâm nên cộng dồn cả `dx` lẫn `dy`:

| Điểm | Toạ độ trên path | Cách (512,512) | Cộng 17px nét viền |
|---|---|---|---|
| Mũi đáy | (512, 764) | 252px | 269px |
| Giữa cạnh trên | (512, 222) | 290px | 307px |
| Vai (rộng nhất) | (710, 300) | 290px | 307px |
| **Góc trên–vai** | **(690, 254)** | **313px** | **330px** ❌ |

330px vượt ngưỡng 312px. Vì vậy toàn bộ nhóm khiên + mạch được bọc trong một
phép **`scale(0.93)` quanh tâm canvas**:

```
transform="translate(512 512) scale(0.93) translate(-512 -512)"
```

Bao ngoài thật sau khi scale: `330 × 0.93 = 307px`, dư 5px. Phép scale áp lên cả
nét viền (SVG scale nét viền theo transform) nên tỉ lệ hình không đổi.

Muốn chỉnh tỉ lệ khiên về sau thì đổi **con số 0.93** đó, đừng đổi toạ độ path —
và luôn để test safe zone tự nói cho biết đã vượt ngưỡng chưa, đừng tính tay.

Mũi đáy là góc nhọn nên phải dùng `stroke-linejoin="round"`; với `miter` mặc
định, mối nối sẽ vọt ra xa hơn 17px và phá vỡ tính toán trên.

Ràng buộc này được kiểm tự động ở §5.1 trên layer monochrome.

### 3.5 Bốn biến thể

| Layer | Nội dung | Nền |
|---|---|---|
| `icon_full` | đầy đủ, dùng cho iOS + web | gradient đen, đục |
| `icon_foreground` | chỉ khiên + mạch + glow | trong suốt |
| `icon_background` | chỉ gradient nền | đục |
| `icon_monochrome` | silhouette khiên đặc + mạch khoét rỗng, một màu trắng, **không** gradient, **không** glow | trong suốt |

Layer monochrome phục vụ themed icon của Android 13+. Hệ thống tô lại layer này
bằng màu lấy từ wallpaper người dùng, nên mọi gradient và glow đều vô nghĩa ở
đó — phải vẽ riêng dưới dạng khối đặc.

## 4. Pipeline

### 4.1 File nguồn

```
assets/branding/
  icon_full.svg
  icon_foreground.svg
  icon_background.svg
  icon_monochrome.svg
  preview.html          # trang xem thử, không tham gia build
  render.mjs            # điều khiển Chrome headless
  verify.mjs            # kiểm tra asset sinh ra
  generated/            # PNG 1024×1024 do render.mjs tạo
```

Bốn file SVG tách rời thay vì một file có layer bật/tắt: mỗi file tự nó render
được, không cần logic chọn layer, và khi mở ra sửa thì thấy đúng cái sắp thành
PNG.

Các file này **không** khai báo vào `flutter: assets:` trong `pubspec.yaml`.
Chúng là input lúc build, không phải asset runtime; khai báo vào chỉ làm phình
app bundle vô ích.

### 4.2 Bước 1 — Render

`render.mjs` gọi Chrome headless trên từng SVG, ghi ra `generated/*.png` ở
1024×1024:

```
chrome --headless --screenshot --window-size=1024,1024 \
       --default-background-color=00000000
```

Cờ `--default-background-color=00000000` là bắt buộc: mặc định Chrome chèn nền
trắng, làm hỏng hai layer foreground và monochrome.

Dò đường dẫn Chrome theo thứ tự: biến môi trường `CHROME_PATH` →
`C:\Program Files\Google\Chrome\Application\chrome.exe` → `msedge.exe`. Không
tìm thấy thì thoát với thông báo lỗi rõ ràng, không im lặng tạo file rỗng.

### 4.3 Bước 2 — Checkpoint xem thử (chặn bước 3)

Mở `preview.html` cho người dùng duyệt. Trang này hiển thị:

- Icon ở 1024 / 192 / 96 / 48px
- Mô phỏng mask tròn và mask squircle của Android
- Vòng safe-zone vẽ đè lên
- Bản monochrome trên 4 nền màu wallpaper khác nhau

**Chỉ chạy bước 3 sau khi người dùng duyệt xong.** Fan-out ghi đè hàng chục
file; không nên thực hiện khi design còn có thể thay đổi.

### 4.4 Bước 3 — Fan-out

Thêm `flutter_launcher_icons` vào `dev_dependencies` và khối cấu hình trong
`pubspec.yaml`:

```yaml
flutter_launcher_icons:
  image_path: assets/branding/generated/icon_full.png
  android: true
  adaptive_icon_foreground: assets/branding/generated/icon_foreground.png
  adaptive_icon_background: assets/branding/generated/icon_background.png
  adaptive_icon_monochrome: assets/branding/generated/icon_monochrome.png
  ios: true
  remove_alpha_ios: true
  web:
    generate: true
    background_color: "#0A0F14"
    theme_color: "#18FFFF"
```

`dart run flutter_launcher_icons` sinh ra:

- 5 thư mục `mipmap-*` + `mipmap-anydpi-v26/ic_launcher.xml`
- 15 file trong `AppIcon.appiconset` + `Contents.json`
- `web/favicon.png` + `web/icons/*`

`remove_alpha_ios: true` là bắt buộc — App Store Connect từ chối binary có kênh
alpha trong icon 1024×1024.

### 4.5 Bước 4 — Dọn phần package bỏ sót

`flutter_launcher_icons` chỉ chạm vào phần icon của `web/manifest.json`. Sửa tay
các trường còn lại cho khớp thương hiệu:

- `name` / `short_name`: `AegisNet`
- `description`: mô tả thật của app, thay `"A new Flutter project."`
- `background_color`: `#0A0F14`
- `theme_color`: `#18FFFF`

Kiểm tra `web/index.html` xem còn tham chiếu icon cũ không.

## 5. Kiểm chứng

### 5.1 Tầng 1 — `verify.mjs`

Node thuần, đọc header PNG và dùng `zlib` có sẵn, không thêm dependency. Thoát
với exit code khác 0 khi có mục sai, in ra đúng mục nào sai.

| Kiểm tra | Lý do |
|---|---|
| Mọi file sinh ra tồn tại và đúng kích thước | Bắt trường hợp package chạy nửa chừng hoặc thiếu một dpi |
| **Safe zone**: mọi pixel không trong suốt của `icon_monochrome.png` nằm trong bán kính 312px từ tâm | Kiểm tự động ràng buộc §3.4. Chọn layer monochrome vì nó không có glow — glow được phép tràn ra ngoài nên không kiểm được trên foreground |
| `icon_foreground.png` và `icon_monochrome.png` có alpha, 4 pixel góc trong suốt | Lỗi Chrome headless hay gặp nhất — chèn nền trắng, khiến foreground hiện thành ô vuông trắng trên home screen |
| `Icon-App-1024x1024@1x.png` không có pixel trong suốt | App Store Connect từ chối thẳng binary vi phạm |
| `mipmap-anydpi-v26/ic_launcher.xml` tồn tại và trỏ đúng 3 layer | Thiếu thì Android im lặng tụt về icon legacy, không báo lỗi |

### 5.2 Tầng 2 — Build thật

`flutter analyze` (bắt lỗi cú pháp pubspec), rồi `flutter build apk --debug`.
Bước build là chỗ duy nhất chứng minh XML adaptive icon hợp lệ — `aapt` sẽ fail
nếu tham chiếu layer sai.

iOS không build được trên Windows. Phần iOS dừng ở kiểm tra sự tồn tại của file
và tính hợp lệ schema của `Contents.json`.

### 5.3 Tầng 3 — Mắt người

Người dùng duyệt `preview.html`. Câu hỏi cần trả lời: **ở 48px nó còn đọc ra
hình khiên không?** Đó là bài kiểm tra thật sự của một app icon và không script
nào thay thế được.

### 5.4 Phần không kiểm chứng được

Không cài được app lên thiết bị Android/iOS thật để xem icon trên home screen.
Nếu người dùng có thiết bị, `flutter install` sau khi build là bước xác nhận
cuối. Phần này phải được nêu rõ là **chưa kiểm chứng**, không tuyên bố hoàn tất
thay người dùng.

## 6. Chiến lược commit và rollback

Yêu cầu cốt lõi: **asset của nền tảng (`android/`, `ios/`, `web/`) phải nằm
trong commit riêng, không trộn với file nguồn thiết kế** — để revert được phần
asset mà vẫn giữ bản thiết kế và bộ công cụ.

Kế hoạch triển khai chia nhỏ hơn thế thành từng commit một-task-một-commit cho
dễ review, nhưng vẫn giữ đúng ranh giới trên: nhóm commit đầu là công cụ + SVG +
PNG 1024 sinh ra, sau đó **một commit riêng** cho toàn bộ fan-out ra nền tảng.

Mọi file bị ghi đè đều đang được git theo dõi; `git checkout -- android/ ios/
web/` hoàn tác sạch.

## 7. Quyết định đã chốt

| Quyết định | Lựa chọn | Phương án bị loại |
|---|---|---|
| Motif | Khiên + mạch điện tử | Khiên đặc tối giản; monogram chữ A; khiên + dấu cấm |
| Bảng màu | Nền đen + neon cyan | Gradient cyan→teal nền sáng; gradient cyan→tím |
| Phạm vi | Android + iOS + web | Chỉ Android + iOS; hoặc thêm cả splash screen |
| Cách sinh asset | SVG + Chrome headless + `flutter_launcher_icons` | Flutter CustomPainter; SVG + Chrome tự sinh mọi thứ bằng tay |

**Phương án dự phòng:** nếu `flutter pub get` không lấy được
`flutter_launcher_icons` (không có mạng), tụt xuống phương án tự sinh: Chrome
render thẳng ra từng kích thước, `Contents.json` / XML adaptive icon /
`manifest.json` viết tay. Phần SVG giữ nguyên, không phí công.
