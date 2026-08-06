class AppStrings {
  static String lang = 'en';

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
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
    },
    'vi': {
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
    },
    'ko': {
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
    },
    'ja': {
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
      'theme_title': 'サイバーパンクネ온カラー',
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
    },
  };

  static String get(String key) {
    return _localizedValues[lang]?[key] ?? _localizedValues['en']![key] ?? key;
  }

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
