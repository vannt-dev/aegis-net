/// Every user-visible string in the app, in the four languages the settings
/// screen offers.
///
/// Only the dashboard and part of the settings screen used to go through here;
/// Rules, Analytics, Logs and the navigation bar were hardcoded English, so
/// switching language changed about a quarter of the app. The keys below cover
/// all six screens.
///
/// Placeholders: `%s` for a single value, `%1` / `%2` where a string takes two.
class AppStrings {
  static String lang = 'en';

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // ---------------------------------------------------------- dashboard
      'app_title': 'AEGIS NET',
      'app_subtitle': 'Rust-Powered Privacy Guard',
      'protected': 'PROTECTED',
      'unprotected': 'UNPROTECTED',
      'paused': 'PAUSED',
      'tap_to_start': 'TAP TO START',
      'connecting': 'CONNECTING',
      'total_queries': 'Total Queries',
      'ads_blocked': 'Ads Blocked',
      'block_rate': 'Block Rate',
      'data_saved': 'Data Saved',
      'traffic_overview': 'Traffic & Latency',
      'pause': 'Pause',
      'resume_now': 'RESUME NOW',
      'rules_title': 'Filter Rules & Engine',
      'logs_title': 'Live Query Logs',
      'analytics_title': 'Detailed Analytics & Reports',
      'settings_title': 'Settings & Extensions',
      'theme_title': 'Cyberpunk Accent Color',
      'language_title': 'App Language',
      'export_json': 'EXPORT JSON',
      'speed_test': 'SPEED TEST',
      'export_logs': 'EXPORT LOGS (CSV)',
      'vpn_diagnostics': 'VPN DIAGNOSTICS',
      'vpn_err_consent_denied':
          'VPN permission was declined. Tap the power button again and choose OK.',
      'vpn_err_consent_unavailable':
          'This ROM did not show the VPN permission dialog. On Xiaomi/MIUI: Settings > Apps > AegisNet, enable "Autostart" and "Display pop-up windows while running in the background", then try again.',
      'vpn_err_not_established':
          'The system refused to create the VPN. On Xiaomi/MIUI: remove other VPN profiles under Settings > Connection & sharing > VPN, set AegisNet battery saver to "No restrictions", then try again.',
      'vpn_err_timeout':
          'Timed out waiting for the tunnel to start. Reopen the app and try again.',
      'vpn_err_generic': 'Could not start the VPN',
      'private_dns_title': 'Private DNS is bypassing AegisNet',
      'private_dns_body':
          'This device is set to a fixed Private DNS provider, so Android sends every lookup straight to it and AegisNet never sees them. Nothing is being filtered. Set Private DNS to "Automatic" or "Off" to restore blocking.',
      'private_dns_action': 'OPEN PRIVATE DNS SETTINGS',
      'desktop_proxy_title': 'Nothing is filtered yet',
      'desktop_proxy_ready':
          'Desktop cannot capture DNS on its own. AegisNet is answering queries on 127.0.0.1 — set that as your system DNS server and filtering starts.',
      'desktop_proxy_high_port':
          'Desktop cannot capture DNS on its own, and port 53 was unavailable, so AegisNet is on 127.0.0.1:%s. System DNS settings only accept an address without a port, so this cannot be used as your resolver — test it with: dig -p %s @127.0.0.1 example.com',

      // ------------------------------------------------------------- common
      'common_cancel': 'CANCEL',
      'common_close': 'CLOSE',
      'common_add': 'ADD',
      'common_restore': 'RESTORE',

      // --------------------------------------------------------- navigation
      'nav_dashboard': 'Dashboard',
      'nav_rules': 'Rules',
      'nav_logs': 'Logs',
      'nav_analytics': 'Analytics',
      'nav_settings': 'Settings',

      // ---------------------------------------------------------- analytics
      'analytics_top_blocked': 'Top Blocked Ad Networks',
      'analytics_no_blocked': 'No blocked queries yet',
      'analytics_top_requested': 'Top Requested Domains',
      'analytics_no_resolved': 'No resolved queries yet',
      'analytics_recent_rate': 'Recent Query Rate',
      'analytics_no_traffic': 'No traffic recorded yet',

      // --------------------------------------------------------------- logs
      'logs_filter_hint': 'Filter domain logs...',
      'logs_chip_all': 'ALL LOGS',
      'logs_blocked': 'BLOCKED',
      'logs_allowed': 'ALLOWED',
      'logs_empty': 'No queries captured yet',

      // -------------------------------------------------------------- rules
      'rules_synced_count': 'Successfully synced %s active ad-blocking rules!',
      'rules_synced': 'Synced filter lists with active engine.',
      'rules_add_url_title': 'Add Custom Blocklist URL',
      'rules_list_name_hint': 'List Name (e.g. OISD Basic)',
      'rules_enter_name_url': 'Enter a name and an http(s) URL',
      'rules_custom_desc': 'User custom filter list',
      'rules_already_subscribed': 'That list is already subscribed',
      'rules_add_list': 'ADD LIST',
      'rules_sync_tooltip': 'Sync Live Rules',
      'rules_tab_presets': 'Filter Presets',
      'rules_tab_custom': 'Custom Rules',
      'rules_tab_hosts': 'Local DNS Hosts',
      'rules_subscribe': 'Subscribe to Filter Lists',
      'rules_add_url': 'ADD URL',
      'rules_add_domain': 'Add Custom Domain Rule',
      'rules_domain_hint': 'e.g. example.com',
      'rules_allow': 'ALLOW',
      'rules_block': 'BLOCK',
      'rules_whitelist_title': 'Custom Whitelist (Always Allowed)',
      'rules_no_whitelist': 'No custom whitelisted domains',
      'rules_hosts_desc':
          'Override DNS resolution locally without remote server lookup.',
      'rules_host_domain_hint': 'Domain (e.g. myrouter.local)',
      'rules_host_ip_hint': 'IP (192.168.1.1)',
      'rules_enter_domain_map': 'Enter a domain to map',
      'rules_map': 'MAP',
      'rules_active_mappings': 'Active Custom Mappings',
      'rules_no_mappings': 'No custom host mappings defined',

      // ----------------------------------------------------------- settings
      'settings_measuring': 'Measuring DNS Latency...',
      'settings_fastest': 'FASTEST',
      'settings_upstream': 'Upstream DNS Resolver',
      'dns_cloudflare_desc': 'Fastest privacy-focused resolver',
      'dns_google_desc': 'High reliability global resolver',
      'dns_adguard_desc': 'Upstream ad-blocking DNS',
      'dns_quad9_desc': 'Malware protection & threat blocking',
      'settings_doh_hint':
          'Custom DoH URL (e.g. https://dns.nextdns.io/xxxxxx)',
      'settings_split_title': 'App-by-App Split Tunneling (Bypass VPN)',
      'settings_split_desc':
          'Selected apps will bypass Aegis Local VPN and connect directly.',
      'settings_pkg_hint': 'Package name (e.g. com.example.app)',
      'settings_schedule_title': 'Scheduled Parental Controls',
      'settings_schedule_desc':
          'Enforces Adult content filtering from %1 to %2, then restores your own setting.',
      'settings_backup_title': 'Configuration Backup & Restore',
      'settings_backup_json': 'BACKUP JSON',
      'settings_exported_title': 'Exported Configuration JSON',
      'settings_restore_json': 'RESTORE JSON',
      'settings_paste_title': 'Paste Configuration JSON',
      'settings_paste_hint': 'Paste JSON here...',
      'settings_restored_ok': 'Config restored successfully!',
      'settings_invalid_json': 'Invalid JSON config format',
      'settings_ios_profile': 'Install iOS Encrypted DNS Profile',
      'settings_profile_ok':
          'Profile generated! Review & Install in iOS Settings > Profile Downloaded.',
      'settings_profile_failed': 'Failed to generate profile.',
      'count_blocked': '%s blocked',
      'count_queries': '%s queries',
      'benchmark_results': '⚡ DNS Benchmark Results',

      // ------------------------------------------------ filter list metadata
      'src_adguard_dns_name': 'AdGuard DNS Filter',
      'src_adguard_dns_desc':
          'Official AdGuard DNS filter for mobile apps and trackers.',
      'src_stevenblack_name': 'StevenBlack Unified Hosts',
      'src_stevenblack_desc':
          'Consolidated host file blocking adservers and malware.',
      'src_pgl_yoyo_name': "Peter Lowe's Ad and Tracking Server List",
      'src_pgl_yoyo_desc':
          'Hand-curated ad and tracking servers. Small, low false positives.',
      'src_oisd_small_name': 'OISD Small',
      'src_oisd_small_desc':
          'Curated aggregate of ad and tracking domains, tuned to avoid breaking sites.',
      'src_urlhaus_name': 'URLhaus Malware Hosts',
      'src_urlhaus_desc': 'abuse.ch feed of hosts actively serving malware.',
      'src_stevenblack_porn_name': 'StevenBlack Adult Hosts',
      'src_stevenblack_porn_desc':
          'Adult sites only. Enable to make the Adult filter do anything; adds about 4 MB of memory.',
      'samples_none': 'No samples yet',
      'samples_last': 'Last %s samples',
    },
    'vi': {
      // ---------------------------------------------------------- dashboard
      'app_title': 'AEGIS NET',
      'app_subtitle': 'Tường lửa Bảo mật nhân Rust',
      'protected': 'ĐÃ BẢO VỆ',
      'unprotected': 'CHƯA BẢO VỆ',
      'paused': 'TẠM DỪNG',
      'tap_to_start': 'BẤM ĐỂ BẬT',
      'connecting': 'ĐANG KẾT NỐI',
      'total_queries': 'Tổng Truy Vấn',
      'ads_blocked': 'Quảng Cáo Đã Chặn',
      'block_rate': 'Tỷ Lệ Chặn',
      'data_saved': 'Dung Lượng Tiết Kiệm',
      'traffic_overview': 'Lưu Lượng & Độ Trễ',
      'pause': 'Tạm dừng',
      'resume_now': 'BẬT LẠI NGAY',
      'rules_title': 'Quy Tắc & Bộ Lọc',
      'logs_title': 'Nhật Ký Truy Vấn Live',
      'analytics_title': 'Báo Cáo & Thống Kê Chi Tiết',
      'settings_title': 'Cài Đặt & Tiện Ích',
      'theme_title': 'Tông Màu Cyberpunk Neon',
      'language_title': 'Ngôn Ngữ Ứng Dụng',
      'export_json': 'XUẤT FILE JSON',
      'speed_test': 'ĐO TỐC ĐỘ DNS',
      'export_logs': 'XUẤT LOGS (CSV)',
      'vpn_diagnostics': 'CHẨN ĐOÁN VPN',
      'vpn_err_consent_denied':
          'Bạn đã từ chối quyền VPN. Bấm nút nguồn lần nữa và chọn "OK".',
      'vpn_err_consent_unavailable':
          'Máy không hiện hộp thoại cấp quyền VPN. Trên Xiaomi/MIUI: Cài đặt > Ứng dụng > AegisNet, bật "Tự khởi động" và "Hiển thị cửa sổ pop-up khi chạy nền", rồi thử lại.',
      'vpn_err_not_established':
          'Hệ thống từ chối tạo VPN. Trên Xiaomi/MIUI: xoá các hồ sơ VPN khác trong Cài đặt > Kết nối & chia sẻ > VPN, đặt tiết kiệm pin của AegisNet thành "Không giới hạn", rồi thử lại.',
      'vpn_err_timeout':
          'Hết thời gian chờ khởi động VPN. Hãy mở lại ứng dụng và thử lại.',
      'vpn_err_generic': 'Không bật được VPN',
      'private_dns_title': 'Private DNS đang đi vòng qua AegisNet',
      'private_dns_body':
          'Máy đang đặt Private DNS cố định nên Android gửi thẳng mọi truy vấn tới nhà cung cấp đó, AegisNet không nhìn thấy gì. Hiện không có gì được lọc. Hãy đổi Private DNS sang "Tự động" hoặc "Tắt" để chặn hoạt động trở lại.',
      'private_dns_action': 'MỞ CÀI ĐẶT PRIVATE DNS',
      'desktop_proxy_title': 'Chưa lọc được gì',
      'desktop_proxy_ready':
          'Máy tính không tự chặn được DNS. AegisNet đang trả lời truy vấn ở 127.0.0.1 — hãy đặt địa chỉ này làm DNS hệ thống thì việc lọc mới bắt đầu.',
      'desktop_proxy_high_port':
          'Máy tính không tự chặn được DNS, và cổng 53 đang bận nên AegisNet nằm ở 127.0.0.1:%s. Cài đặt DNS hệ thống chỉ nhận địa chỉ không kèm cổng, nên không dùng làm resolver được — thử bằng: dig -p %s @127.0.0.1 example.com',

      // ------------------------------------------------------------- common
      'common_cancel': 'HUỶ',
      'common_close': 'ĐÓNG',
      'common_add': 'THÊM',
      'common_restore': 'KHÔI PHỤC',

      // --------------------------------------------------------- navigation
      'nav_dashboard': 'Tổng quan',
      'nav_rules': 'Quy tắc',
      'nav_logs': 'Nhật ký',
      'nav_analytics': 'Thống kê',
      'nav_settings': 'Cài đặt',

      // ---------------------------------------------------------- analytics
      'analytics_top_blocked': 'Mạng Quảng Cáo Bị Chặn Nhiều Nhất',
      'analytics_no_blocked': 'Chưa có truy vấn nào bị chặn',
      'analytics_top_requested': 'Tên Miền Được Truy Vấn Nhiều Nhất',
      'analytics_no_resolved': 'Chưa có truy vấn nào được phân giải',
      'analytics_recent_rate': 'Tốc Độ Truy Vấn Gần Đây',
      'analytics_no_traffic': 'Chưa ghi nhận lưu lượng nào',

      // --------------------------------------------------------------- logs
      'logs_filter_hint': 'Lọc theo tên miền...',
      'logs_chip_all': 'TẤT CẢ',
      'logs_blocked': 'ĐÃ CHẶN',
      'logs_allowed': 'CHO QUA',
      'logs_empty': 'Chưa ghi nhận truy vấn nào',

      // -------------------------------------------------------------- rules
      'rules_synced_count': 'Đã đồng bộ %s quy tắc chặn quảng cáo!',
      'rules_synced': 'Đã đồng bộ danh sách lọc với engine.',
      'rules_add_url_title': 'Thêm URL Danh Sách Chặn',
      'rules_list_name_hint': 'Tên danh sách (vd: OISD Basic)',
      'rules_enter_name_url': 'Nhập tên và một URL http(s)',
      'rules_custom_desc': 'Danh sách lọc tự thêm',
      'rules_already_subscribed': 'Danh sách này đã được đăng ký',
      'rules_add_list': 'THÊM DANH SÁCH',
      'rules_sync_tooltip': 'Đồng bộ quy tắc',
      // Kept short: three tabs share the width and the longer wording clipped.
      'rules_tab_presets': 'Có sẵn',
      'rules_tab_custom': 'Quy tắc riêng',
      'rules_tab_hosts': 'DNS nội bộ',
      'rules_subscribe': 'Đăng Ký Danh Sách Lọc',
      'rules_add_url': 'THÊM URL',
      'rules_add_domain': 'Thêm Quy Tắc Tên Miền',
      'rules_domain_hint': 'vd: example.com',
      'rules_allow': 'CHO PHÉP',
      'rules_block': 'CHẶN',
      'rules_whitelist_title': 'Danh Sách Cho Phép (Luôn Bỏ Qua)',
      'rules_no_whitelist': 'Chưa có tên miền nào được cho phép',
      'rules_hosts_desc':
          'Ghi đè phân giải DNS ngay tại máy, không hỏi máy chủ từ xa.',
      'rules_host_domain_hint': 'Tên miền (vd: myrouter.local)',
      'rules_host_ip_hint': 'IP (192.168.1.1)',
      'rules_enter_domain_map': 'Nhập tên miền cần ánh xạ',
      'rules_map': 'ÁNH XẠ',
      'rules_active_mappings': 'Ánh Xạ Đang Hoạt Động',
      'rules_no_mappings': 'Chưa định nghĩa ánh xạ nào',

      // ----------------------------------------------------------- settings
      'settings_measuring': 'Đang đo độ trễ DNS...',
      'settings_fastest': 'NHANH NHẤT',
      'settings_upstream': 'Máy Chủ DNS Đầu Nguồn',
      'dns_cloudflare_desc': 'Nhanh nhất, chú trọng riêng tư',
      'dns_google_desc': 'Ổn định cao trên toàn cầu',
      'dns_adguard_desc': 'DNS chặn quảng cáo từ đầu nguồn',
      'dns_quad9_desc': 'Chặn mã độc và các mối đe doạ',
      'settings_doh_hint':
          'URL DoH tự chọn (vd: https://dns.nextdns.io/xxxxxx)',
      'settings_split_title': 'Chia Đường Truyền Theo Ứng Dụng (Bỏ Qua VPN)',
      'settings_split_desc':
          'Ứng dụng được chọn sẽ không đi qua VPN của Aegis mà kết nối thẳng.',
      'settings_pkg_hint': 'Tên package (vd: com.example.app)',
      'settings_schedule_title': 'Hẹn Giờ Kiểm Soát Trẻ Em',
      'settings_schedule_desc':
          'Bật lọc nội dung người lớn từ %1 đến %2, sau đó trả lại thiết lập của bạn.',
      'settings_backup_title': 'Sao Lưu & Khôi Phục Cấu Hình',
      'settings_backup_json': 'SAO LƯU JSON',
      'settings_exported_title': 'JSON Cấu Hình Đã Xuất',
      'settings_restore_json': 'KHÔI PHỤC JSON',
      'settings_paste_title': 'Dán JSON Cấu Hình',
      'settings_paste_hint': 'Dán JSON vào đây...',
      'settings_restored_ok': 'Đã khôi phục cấu hình!',
      'settings_invalid_json': 'JSON cấu hình không hợp lệ',
      'settings_ios_profile': 'Cài Hồ Sơ DNS Mã Hoá cho iOS',
      'settings_profile_ok':
          'Đã tạo hồ sơ! Vào Cài đặt iOS > Đã tải hồ sơ để xem lại và cài đặt.',
      'settings_profile_failed': 'Không tạo được hồ sơ.',
      'count_blocked': 'đã chặn %s',
      'count_queries': '%s truy vấn',
      'benchmark_results': '⚡ Kết Quả Đo Tốc Độ DNS',

      // ------------------------------------------------ filter list metadata
      'src_adguard_dns_name': 'Bộ lọc AdGuard DNS',
      'src_adguard_dns_desc':
          'Bộ lọc DNS chính thức của AdGuard cho ứng dụng di động và trình theo dõi.',
      'src_stevenblack_name': 'StevenBlack Unified Hosts',
      'src_stevenblack_desc':
          'Tệp hosts tổng hợp, chặn máy chủ quảng cáo và mã độc.',
      'src_pgl_yoyo_name': 'Danh sách máy chủ quảng cáo của Peter Lowe',
      'src_pgl_yoyo_desc': 'Chọn lọc thủ công. Nhỏ gọn, ít chặn nhầm.',
      'src_oisd_small_name': 'OISD Small',
      'src_oisd_small_desc':
          'Tổng hợp có chọn lọc các tên miền quảng cáo và theo dõi, hạn chế làm hỏng trang web.',
      'src_urlhaus_name': 'URLhaus — Máy chủ phát tán mã độc',
      'src_urlhaus_desc': 'Nguồn abuse.ch, các máy chủ đang phát tán mã độc.',
      'src_stevenblack_porn_name': 'StevenBlack — Nội dung người lớn',
      'src_stevenblack_porn_desc':
          'Chỉ gồm trang người lớn. Bật thì bộ lọc Người lớn mới có tác dụng; tốn thêm khoảng 4 MB bộ nhớ.',
      'samples_none': 'Chưa có mẫu nào',
      'samples_last': '%s mẫu gần nhất',
    },
    'ko': {
      // ---------------------------------------------------------- dashboard
      'app_title': 'AEGIS NET',
      'app_subtitle': 'Rust 기반 개인정보 보안 방화벽',
      'protected': '보호됨',
      'unprotected': '보호 안 됨',
      'paused': '일시 정지됨',
      'tap_to_start': '탭하여 시작',
      'connecting': '연결 중',
      'total_queries': '총 쿼리 수',
      'ads_blocked': '차단된 광고',
      'block_rate': '차단율',
      'data_saved': '절약된 데이터',
      'traffic_overview': '트래픽 및 지연 시간',
      'pause': '일시 정지',
      'resume_now': '지금 다시 시작',
      'rules_title': '필터 규칙 및 엔진',
      'logs_title': '실시간 쿼리 로그',
      'analytics_title': '상세 분석 및 보고서',
      'settings_title': '설정 및 확장 기능',
      'theme_title': '사이버펑크 네온 테마',
      'language_title': '앱 언어 설정',
      'export_json': 'JSON 내보내기',
      'speed_test': '속도 테스트',
      'export_logs': '로그 내보내기 (CSV)',
      'vpn_diagnostics': 'VPN 진단',
      'vpn_err_consent_denied': 'VPN 권한이 거부되었습니다. 전원 버튼을 다시 누르고 확인을 선택하세요.',
      'vpn_err_consent_unavailable':
          '이 ROM에서 VPN 권한 대화상자가 표시되지 않았습니다. Xiaomi/MIUI: 설정 > 앱 > AegisNet에서 "자동 시작"과 "백그라운드 팝업 표시"를 켠 뒤 다시 시도하세요.',
      'vpn_err_not_established':
          '시스템이 VPN 생성을 거부했습니다. Xiaomi/MIUI: 설정 > 연결 및 공유 > VPN에서 다른 VPN 프로필을 삭제하고, AegisNet의 배터리 절약을 "제한 없음"으로 설정한 뒤 다시 시도하세요.',
      'vpn_err_timeout': '터널 시작 대기 시간이 초과되었습니다. 앱을 다시 열고 시도하세요.',
      'vpn_err_generic': 'VPN을 시작할 수 없습니다',
      'private_dns_title': '비공개 DNS가 AegisNet을 우회하고 있습니다',
      'private_dns_body':
          '이 기기는 고정 비공개 DNS 제공업체로 설정되어 있어 Android가 모든 조회를 그쪽으로 직접 보내므로 AegisNet은 아무것도 볼 수 없습니다. 현재 필터링되는 것이 없습니다. 차단을 되돌리려면 비공개 DNS를 "자동" 또는 "사용 안 함"으로 설정하세요.',
      'private_dns_action': '비공개 DNS 설정 열기',
      'desktop_proxy_title': '아직 아무것도 필터링되지 않습니다',
      'desktop_proxy_ready':
          '데스크톱은 스스로 DNS를 가로챌 수 없습니다. AegisNet이 127.0.0.1에서 쿼리에 응답하고 있으니, 이를 시스템 DNS 서버로 지정하면 필터링이 시작됩니다.',
      'desktop_proxy_high_port':
          '데스크톱은 스스로 DNS를 가로챌 수 없고 53 포트를 사용할 수 없어 AegisNet은 127.0.0.1:%s 에 있습니다. 시스템 DNS 설정은 포트 없는 주소만 받으므로 리졸버로 쓸 수 없습니다 — 다음으로 테스트하세요: dig -p %s @127.0.0.1 example.com',

      // ------------------------------------------------------------- common
      'common_cancel': '취소',
      'common_close': '닫기',
      'common_add': '추가',
      'common_restore': '복원',

      // --------------------------------------------------------- navigation
      'nav_dashboard': '대시보드',
      'nav_rules': '규칙',
      'nav_logs': '로그',
      'nav_analytics': '분석',
      'nav_settings': '설정',

      // ---------------------------------------------------------- analytics
      'analytics_top_blocked': '가장 많이 차단된 광고 네트워크',
      'analytics_no_blocked': '아직 차단된 쿼리가 없습니다',
      'analytics_top_requested': '요청이 많은 도메인',
      'analytics_no_resolved': '아직 처리된 쿼리가 없습니다',
      'analytics_recent_rate': '최근 쿼리 속도',
      'analytics_no_traffic': '아직 기록된 트래픽이 없습니다',

      // --------------------------------------------------------------- logs
      'logs_filter_hint': '도메인으로 검색...',
      'logs_chip_all': '전체',
      'logs_blocked': '차단됨',
      'logs_allowed': '허용됨',
      'logs_empty': '아직 수집된 쿼리가 없습니다',

      // -------------------------------------------------------------- rules
      'rules_synced_count': '차단 규칙 %s개를 동기화했습니다!',
      'rules_synced': '필터 목록을 엔진과 동기화했습니다.',
      'rules_add_url_title': '사용자 차단 목록 URL 추가',
      'rules_list_name_hint': '목록 이름 (예: OISD Basic)',
      'rules_enter_name_url': '이름과 http(s) URL을 입력하세요',
      'rules_custom_desc': '사용자 지정 필터 목록',
      'rules_already_subscribed': '이미 구독 중인 목록입니다',
      'rules_add_list': '목록 추가',
      'rules_sync_tooltip': '실시간 규칙 동기화',
      'rules_tab_presets': '필터 프리셋',
      'rules_tab_custom': '사용자 규칙',
      'rules_tab_hosts': '로컬 DNS 호스트',
      'rules_subscribe': '필터 목록 구독',
      'rules_add_url': 'URL 추가',
      'rules_add_domain': '도메인 규칙 추가',
      'rules_domain_hint': '예: example.com',
      'rules_allow': '허용',
      'rules_block': '차단',
      'rules_whitelist_title': '사용자 허용 목록 (항상 허용)',
      'rules_no_whitelist': '허용 목록이 비어 있습니다',
      'rules_hosts_desc': '원격 서버 조회 없이 로컬에서 DNS 결과를 지정합니다.',
      'rules_host_domain_hint': '도메인 (예: myrouter.local)',
      'rules_host_ip_hint': 'IP (192.168.1.1)',
      'rules_enter_domain_map': '매핑할 도메인을 입력하세요',
      'rules_map': '매핑',
      'rules_active_mappings': '활성 매핑 목록',
      'rules_no_mappings': '정의된 매핑이 없습니다',

      // ----------------------------------------------------------- settings
      'settings_measuring': 'DNS 지연 시간 측정 중...',
      'settings_fastest': '가장 빠름',
      'settings_upstream': '업스트림 DNS 서버',
      'dns_cloudflare_desc': '가장 빠르고 프라이버시 중심',
      'dns_google_desc': '전 세계적으로 안정적',
      'dns_adguard_desc': '광고 차단 기능이 있는 DNS',
      'dns_quad9_desc': '악성코드 및 위협 차단',
      'settings_doh_hint': '사용자 DoH URL (예: https://dns.nextdns.io/xxxxxx)',
      'settings_split_title': '앱별 분할 터널링 (VPN 우회)',
      'settings_split_desc': '선택한 앱은 Aegis VPN을 우회해 직접 연결됩니다.',
      'settings_pkg_hint': '패키지 이름 (예: com.example.app)',
      'settings_schedule_title': '예약된 자녀 보호',
      'settings_schedule_desc': '%1부터 %2까지 성인 콘텐츠 필터를 적용한 뒤 원래 설정으로 되돌립니다.',
      'settings_backup_title': '설정 백업 및 복원',
      'settings_backup_json': 'JSON 백업',
      'settings_exported_title': '내보낸 설정 JSON',
      'settings_restore_json': 'JSON 복원',
      'settings_paste_title': '설정 JSON 붙여넣기',
      'settings_paste_hint': '여기에 JSON을 붙여넣으세요...',
      'settings_restored_ok': '설정을 복원했습니다!',
      'settings_invalid_json': '잘못된 JSON 설정 형식입니다',
      'settings_ios_profile': 'iOS 암호화 DNS 프로파일 설치',
      'settings_profile_ok': '프로파일을 생성했습니다! iOS 설정 > 다운로드된 프로파일에서 확인 후 설치하세요.',
      'settings_profile_failed': '프로파일 생성에 실패했습니다.',
      'count_blocked': '%s회 차단',
      'count_queries': '%s회 요청',
      'benchmark_results': '⚡ DNS 속도 측정 결과',

      // ------------------------------------------------ filter list metadata
      'src_adguard_dns_name': 'AdGuard DNS 필터',
      'src_adguard_dns_desc': '모바일 앱과 트래커를 겨냥한 AdGuard 공식 DNS 필터입니다.',
      'src_stevenblack_name': 'StevenBlack 통합 호스트',
      'src_stevenblack_desc': '광고 서버와 악성코드를 차단하는 통합 hosts 파일입니다.',
      'src_pgl_yoyo_name': 'Peter Lowe 광고·추적 서버 목록',
      'src_pgl_yoyo_desc': '수작업으로 선별한 목록. 작고 오탐이 적습니다.',
      'src_oisd_small_name': 'OISD Small',
      'src_oisd_small_desc': '사이트를 망가뜨리지 않도록 선별한 광고·추적 도메인 모음입니다.',
      'src_urlhaus_name': 'URLhaus 악성코드 호스트',
      'src_urlhaus_desc': '악성코드를 실제로 배포 중인 호스트의 abuse.ch 피드입니다.',
      'src_stevenblack_porn_name': 'StevenBlack 성인 사이트 호스트',
      'src_stevenblack_porn_desc':
          '성인 사이트 전용. 켜야 성인 필터가 동작하며 약 4 MB의 메모리를 더 사용합니다.',
      'samples_none': '아직 샘플이 없습니다',
      'samples_last': '최근 %s개 샘플',
    },
    'ja': {
      // ---------------------------------------------------------- dashboard
      'app_title': 'AEGIS NET',
      'app_subtitle': 'Rust駆動のプライバシーガード',
      'protected': '保護中',
      'unprotected': '未保護',
      'paused': '一時停止中',
      'tap_to_start': 'タップして開始',
      'connecting': '接続中',
      'total_queries': '総クエリ数',
      'ads_blocked': 'ブロックされた広告',
      'block_rate': 'ブロック率',
      'data_saved': '節約されたデータ',
      'traffic_overview': 'トラフィックとレイテンシ',
      'pause': '一時停止',
      'resume_now': '今すぐ再開',
      'rules_title': 'フィルタールールとエンジン',
      'logs_title': 'リアルタイムログ',
      'analytics_title': '詳細分析とレポート',
      'settings_title': '設定と拡張機能',
      'theme_title': 'サイバーパンクネオンカラー',
      'language_title': 'アプリ言語設定',
      'export_json': 'JSONエクスポート',
      'speed_test': 'スピードテスト',
      'export_logs': 'ログエクスポート (CSV)',
      'vpn_diagnostics': 'VPN診断',
      'vpn_err_consent_denied': 'VPNの権限が拒否されました。電源ボタンをもう一度押してOKを選択してください。',
      'vpn_err_consent_unavailable':
          'このROMではVPN許可ダイアログが表示されませんでした。Xiaomi/MIUI: 設定 > アプリ > AegisNet で「自動起動」と「バックグラウンドでのポップアップ表示」を有効にしてから再試行してください。',
      'vpn_err_not_established':
          'システムがVPNの作成を拒否しました。Xiaomi/MIUI: 設定 > 接続と共有 > VPN で他のVPNプロファイルを削除し、AegisNetのバッテリー節約を「制限なし」にしてから再試行してください。',
      'vpn_err_timeout': 'トンネル開始の待機がタイムアウトしました。アプリを開き直してください。',
      'vpn_err_generic': 'VPNを開始できませんでした',
      'private_dns_title': 'プライベートDNSがAegisNetを迂回しています',
      'private_dns_body':
          'この端末は固定のプライベートDNSプロバイダに設定されているため、Androidはすべての名前解決をそこへ直接送り、AegisNetは何も受け取りません。現在フィルタリングは行われていません。ブロックを復元するにはプライベートDNSを「自動」または「オフ」に設定してください。',
      'private_dns_action': 'プライベートDNS設定を開く',
      'desktop_proxy_title': 'まだ何もフィルタリングされていません',
      'desktop_proxy_ready':
          'デスクトップは自力でDNSを捕捉できません。AegisNetが127.0.0.1でクエリに応答しているので、これをシステムのDNSサーバーに設定するとフィルタリングが始まります。',
      'desktop_proxy_high_port':
          'デスクトップは自力でDNSを捕捉できず、ポート53も使えなかったため、AegisNetは127.0.0.1:%s にいます。システムのDNS設定はポートなしのアドレスしか受け付けないためリゾルバとしては使えません — 次で確認してください: dig -p %s @127.0.0.1 example.com',

      // ------------------------------------------------------------- common
      'common_cancel': 'キャンセル',
      'common_close': '閉じる',
      'common_add': '追加',
      'common_restore': '復元',

      // --------------------------------------------------------- navigation
      'nav_dashboard': 'ホーム',
      'nav_rules': 'ルール',
      'nav_logs': 'ログ',
      'nav_analytics': '分析',
      'nav_settings': '設定',

      // ---------------------------------------------------------- analytics
      'analytics_top_blocked': 'ブロック上位の広告ネットワーク',
      'analytics_no_blocked': 'ブロックされたクエリはまだありません',
      'analytics_top_requested': 'リクエストの多いドメイン',
      'analytics_no_resolved': '解決されたクエリはまだありません',
      'analytics_recent_rate': '直近のクエリ数',
      'analytics_no_traffic': 'トラフィックはまだ記録されていません',

      // --------------------------------------------------------------- logs
      'logs_filter_hint': 'ドメインで絞り込み...',
      'logs_chip_all': 'すべて',
      'logs_blocked': 'ブロック',
      'logs_allowed': '許可',
      'logs_empty': 'クエリはまだ記録されていません',

      // -------------------------------------------------------------- rules
      'rules_synced_count': '%s件のブロックルールを同期しました！',
      'rules_synced': 'フィルターリストをエンジンと同期しました。',
      'rules_add_url_title': 'カスタムブロックリストURLを追加',
      'rules_list_name_hint': 'リスト名（例: OISD Basic）',
      'rules_enter_name_url': '名前とhttp(s) URLを入力してください',
      'rules_custom_desc': 'ユーザー定義フィルターリスト',
      'rules_already_subscribed': 'そのリストは既に登録されています',
      'rules_add_list': 'リストを追加',
      'rules_sync_tooltip': 'ルールを同期',
      'rules_tab_presets': 'プリセット',
      'rules_tab_custom': 'カスタムルール',
      'rules_tab_hosts': 'ローカルDNSホスト',
      'rules_subscribe': 'フィルターリストを購読',
      'rules_add_url': 'URLを追加',
      'rules_add_domain': 'ドメインルールを追加',
      'rules_domain_hint': '例: example.com',
      'rules_allow': '許可',
      'rules_block': 'ブロック',
      'rules_whitelist_title': 'ホワイトリスト（常に許可）',
      'rules_no_whitelist': '許可リストは空です',
      'rules_hosts_desc': 'リモートサーバーに問い合わせず、ローカルでDNSを上書きします。',
      'rules_host_domain_hint': 'ドメイン（例: myrouter.local）',
      'rules_host_ip_hint': 'IP (192.168.1.1)',
      'rules_enter_domain_map': 'マッピングするドメインを入力してください',
      'rules_map': 'マッピング',
      'rules_active_mappings': '有効なマッピング',
      'rules_no_mappings': 'マッピングは未設定です',

      // ----------------------------------------------------------- settings
      'settings_measuring': 'DNSの遅延を測定中...',
      'settings_fastest': '最速',
      'settings_upstream': '上流DNSリゾルバ',
      'dns_cloudflare_desc': '最速でプライバシー重視',
      'dns_google_desc': '世界的に安定した信頼性',
      'dns_adguard_desc': '広告ブロック機能付きDNS',
      'dns_quad9_desc': 'マルウェアと脅威をブロック',
      'settings_doh_hint': 'カスタムDoH URL（例: https://dns.nextdns.io/xxxxxx）',
      'settings_split_title': 'アプリ別スプリットトンネル（VPN除外）',
      'settings_split_desc': '選択したアプリはAegisのVPNを経由せず直接接続します。',
      'settings_pkg_hint': 'パッケージ名（例: com.example.app）',
      'settings_schedule_title': 'ペアレンタルコントロールのスケジュール',
      'settings_schedule_desc': '%1から%2まで成人向けコンテンツをフィルタし、その後元の設定に戻します。',
      'settings_backup_title': '設定のバックアップと復元',
      'settings_backup_json': 'JSONバックアップ',
      'settings_exported_title': 'エクスポートした設定JSON',
      'settings_restore_json': 'JSON復元',
      'settings_paste_title': '設定JSONを貼り付け',
      'settings_paste_hint': 'ここにJSONを貼り付け...',
      'settings_restored_ok': '設定を復元しました！',
      'settings_invalid_json': 'JSON設定の形式が正しくありません',
      'settings_ios_profile': 'iOS暗号化DNSプロファイルをインストール',
      'settings_profile_ok':
          'プロファイルを生成しました。iOSの設定 > ダウンロード済みプロファイルから確認してインストールしてください。',
      'settings_profile_failed': 'プロファイルの生成に失敗しました。',
      'count_blocked': '%s件ブロック',
      'count_queries': '%s件のクエリ',
      'benchmark_results': '⚡ DNSベンチマーク結果',

      // ------------------------------------------------ filter list metadata
      'src_adguard_dns_name': 'AdGuard DNSフィルター',
      'src_adguard_dns_desc': 'モバイルアプリとトラッカー向けのAdGuard公式DNSフィルターです。',
      'src_stevenblack_name': 'StevenBlack 統合ホスト',
      'src_stevenblack_desc': '広告サーバーとマルウェアをブロックする統合hostsファイルです。',
      'src_pgl_yoyo_name': 'Peter Lowe の広告・追跡サーバー一覧',
      'src_pgl_yoyo_desc': '手作業で選別された一覧。小さく誤検出が少ないです。',
      'src_oisd_small_name': 'OISD Small',
      'src_oisd_small_desc': 'サイトを壊さないよう調整された広告・追跡ドメインの厳選リストです。',
      'src_urlhaus_name': 'URLhaus マルウェアホスト',
      'src_urlhaus_desc': 'マルウェアを実際に配布しているホストのabuse.chフィードです。',
      'src_stevenblack_porn_name': 'StevenBlack アダルトホスト',
      'src_stevenblack_porn_desc':
          'アダルトサイトのみ。有効にするとアダルトフィルターが機能し、約4 MBのメモリを追加で使います。',
      'samples_none': 'サンプルはまだありません',
      'samples_last': '直近%s件のサンプル',
    },
  };

  static String get(String key) {
    return _localizedValues[lang]?[key] ?? _localizedValues['en']![key] ?? key;
  }

  /// [get] for keys that are not expected to exist for every caller.
  ///
  /// A filter list the user added themselves has no translation and never will,
  /// so its name has to fall through to whatever they typed. [get] cannot say
  /// that — it returns the key itself when it finds nothing.
  static String? maybe(String key) =>
      _localizedValues[lang]?[key] ?? _localizedValues['en']![key];

  /// Every key the English table defines. The test that keeps the four
  /// languages in step reads this rather than re-parsing the source.
  static Iterable<String> get keys => _localizedValues['en']!.keys;

  /// Languages offered in settings.
  static Iterable<String> get languages => _localizedValues.keys;

  /// Look up [key] in [lang] only, with no fallback to English. Used by the
  /// parity test — [get] would hide a missing translation behind the fallback.
  static String? rawFor(String language, String key) =>
      _localizedValues[language]?[key];

  /// Native failure codes from MainActivity/AegisVpnService mapped to advice
  /// the user can act on. Unknown codes still surface, with the raw code
  /// appended so a bug report carries it.
  static String vpnError(String code) {
    const messageKeys = <String, String>{
      'consent_denied': 'vpn_err_consent_denied',
      'consent_dialog_unavailable': 'vpn_err_consent_unavailable',
      'vpn_prepare_failed': 'vpn_err_consent_unavailable',
      'tunnel_not_established': 'vpn_err_not_established',
      'tunnel_permission_denied': 'vpn_err_not_established',
      'tunnel_refused': 'vpn_err_not_established',
      'tunnel_start_timeout': 'vpn_err_timeout',
    };

    final key = messageKeys[code];
    return key != null ? get(key) : '${get('vpn_err_generic')} ($code)';
  }
}
