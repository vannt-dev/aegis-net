# 📖 Hướng Dẫn Sử Dụng Ứng Dụng AegisNet (User Guide)

**AegisNet** là ứng dụng tường lửa cá nhân & chặn quảng cáo toàn hệ thống mạnh mẽ, được xây dựng trên nền tảng **Flutter** kết hợp nhân xử lý siêu tốc bằng **Rust Core Engine**.

> **Khả dụng theo nền tảng:** lọc DNS toàn hệ thống đã hoạt động trên **Android**
> (đã kiểm chứng). **iOS** đang hoàn thiện, hiện chỉ chạy giao diện. Trên nền
> tảng không có nhân native, app chạy mô phỏng thuần Dart để giao diện vẫn dùng
> được đầy đủ. Xem [CHANGELOG.md](CHANGELOG.md) để biết chi tiết.

---

## 📋 Mục Lục
1. [Khởi Động & Bật Bảo Vệ Tường Lửa](#1-khởi-động--bật-bảo-vệ-tường-lửa)
2. [Tạm Dừng Bảo Vệ Nhanh (Quick Pause)](#2-tạm-dừng-bảo-vệ-nhanh-quick-pause)
3. [Quản Lý Quy Tắc & Bộ Lọc Quảng Cáo (Rules & Filters)](#3-quản-lý-quy-tắc--bộ-lọc-quảng-cáo-rules--filters)
4. [Xem Nhật Ký Truy Vấn Thời Gian Thực (Live Logs)](#4-xem-nhật-ký-truy-vấn-thời-gian-thực-live-logs)
5. [Xem Thống Kê & Báo Cáo Chi Tiết (Analytics)](#5-xem-thống-kê--báo-cáo-chi-tiết-analytics)
6. [Chế Độ Ngoại Lệ Ứng Dụng (App Split-Tunneling)](#6-chế-độ-ngoại-lệ-ứng-dụng-app-split-tunneling)
7. [Đo Tốc Độ DNS (Speed Test) & Chọn Chủ Đề Neon](#7-đo-tốc-độ-dns-speed-test--chọn-chủ-đề-neon)
8. [Sao Lưu & Phục Hồi Cấu Hình (Export / Import JSON)](#8-sao-lưu--phục-hồi-cấu-hình-export--import-json)

---

## 1. Khởi Động & Bật Bảo Vệ Tường Lửa
* Mở ứng dụng **AegisNet**.
* Tại màn hình **Dashboard**, chạm vào **Nút Nguồn Neon** lớn ở trung tâm màn hình.
* Khi ứng dụng hiển thị nhãn **`PROTECTED`** màu xanh và nút nguồn phát sáng, toàn bộ truy vấn DNS trên thiết bị của bạn đã được bảo vệ.

---

## 2. Tạm Dừng Bảo Vệ Nhanh (Quick Pause)
Khi cần truy cập các trang web hoặc dịch vụ tạm thời bị ảnh hưởng bởi bộ lọc:
* Bên dưới nút nguồn trên màn hình Dashboard, chọn một trong các mốc thời gian tạm dừng:
  * **5m** (Tạm dừng 5 phút)
  * **15m** (Tạm dừng 15 phút)
  * **1h** (Tạm dừng 1 giờ)
* Khi đang tạm dừng, ứng dụng sẽ có đồng hồ đếm ngược. Bạn có thể bấm **`RESUME NOW`** để bật lại bảo vệ ngay lập tức.

---

## 3. Quản Lý Quy Tắc & Bộ Lọc Quảng Cáo (Rules & Filters)
Chuyển sang tab **Rules** trên thanh điều hướng dưới:
* **Preset Filter Lists**: Bật/tắt các danh sách lọc mặc định (AdGuard Mobile, EasyList DNS, StevenBlack Hosts, NoCoin).
* **Nút Đồng bộ 🔄 (Sync Live Rules)**: Bấm biểu tượng xoay ở góc trên bên phải để tải và cập nhật quy tắc chặn ad mới nhất từ internet.
* **Custom Whitelist & Blacklist**:
  * Nhập tên miền (ví dụ: `mybank.com`) và bấm **ALLOW** để luôn cho phép truy cập.
  * Nhập tên miền (ví dụ: `bad-site.com`) và bấm **BLOCK** để luôn chặn.

---

## 4. Xem Nhật Ký Truy Vấn Thời Gian Thực (Live Logs)
Chuyển sang tab **Logs**:
* Theo dõi tất cả truy vấn tên miền của các ứng dụng trên máy theo thời gian thực.
* Nhãn **`BLOCKED` (Đỏ)**: Các truy vấn quảng cáo/theo dõi đã bị ngăn chặn thành công.
* Nhãn **`ALLOWED` (Xanh)**: Các truy vấn an toàn được đi qua.
* Sử dụng ô **Filter domain logs...** ở trên cùng để tìm kiếm tên miền cụ thể.

---

## 5. Xem Thống Kê & Báo Cáo Chi Tiết (Analytics)
Chuyển sang tab **Analytics**:
* Xem **Top 5 Mạng quảng cáo bị chặn nhiều nhất** trên máy của bạn (ví dụ: `doubleclick.net`, `graph.facebook.com`).
* Xem biểu đồ phân bổ số lượng truy vấn theo từng khung giờ trong ngày.

---

## 6. Chế Độ Ngoại Lệ Ứng Dụng (App Split-Tunneling)
Chuyển sang tab **Settings**:
* Tại mục **App-by-App Split Tunneling**, nhập Package Name của ứng dụng (ví dụ: `com.zing.zalo` hoặc `com.vietcombank.mobile`) và bấm **ADD**.
* Các ứng dụng trong danh sách này sẽ đi thẳng ra mạng internet mà không chạy qua Local VPN của AegisNet.

---

## 7. Đo Tốc Độ DNS (Speed Test) & Chọn Chủ Đề Neon
Chuyển sang tab **Settings**:
* **Chủ đề Cyberpunk Neon**: Chọn 1 trong 4 tông màu chủ đề thích mắt (Neon Cyan, Emerald Green, Electric Purple, Sunset Gold).
* **Đo tốc độ DNS**: Bấm nút **`SPEED TEST`** bên cạnh mục Upstream DNS. Hệ thống sẽ đo độ trễ ($ms$) của các nhà cung cấp DNS và hiển thị nhãn **`FASTEST`** cho DNS nhanh nhất để bạn chọn.

---

## 8. Sao Lưu & Phục Hồi Cấu Hình (Export / Import JSON)
* Tại mục **Export / Import Configuration** trong tab Settings:
* Bấm **`EXPORT JSON`** để xuất toàn bộ danh sách Whitelist, Blacklist, app ngoại lệ và cấu hình DNS ra file backup dạng JSON.
