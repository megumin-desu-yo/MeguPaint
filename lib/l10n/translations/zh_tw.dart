/// 繁體中文翻譯
const Map<String, String> zhTW = {
  // 主頁
  'app_title': 'MeguPaint',
  'app_subtitle': '專業繪畫軟體',
  'new_canvas': '新建畫布',
  'open_project': '開啟專案',
  'recent_projects': '最近專案',
  'no_recent_projects': '無最近專案',

  // 新建畫布對話框
  'dialog_new_canvas': '新建畫布',
  'project_name': '專案名稱',
  'untitled_project': '未命名專案',
  'width': '寬度',
  'height': '高度',
  'cancel': '取消',
  'confirm': '確認',
  'create': '建立',

  // 畫布頁面
  'undo': '復原',
  'redo': '重做',
  'save': '儲存',
  'export': '匯出',

  // 工具
  'tool_brush': '畫筆',
  'tool_eraser': '橡皮擦',
  'tool_eyedropper': '吸色器',
  'tool_move': '移動',
  'tool_select': '選擇',
  'tool_rectangle': '矩形',
  'tool_circle': '圓形',
  'tool_line': '直線',
  'tool_fill': '填充',
  'tool_edge_fill': '邊緣填充',
  'tool_text': '文字',

  // 面板
  'panel_color': '顏色',
  'panel_layers': '圖層',
  'new_layer': '新建圖層',
  'background_layer': '背景圖層',

  // 狀態欄
  'zoom': '縮放',
  'tool': '工具',
  'return_home': '返回主頁',

  // 畫布狀態
  'canvas_area': '畫布區域\n(待實現繪圖功能)',
  'canvas_not_loaded': '未載入畫布',

  // 設定
  'settings': '設定',
  'language': '語言',
  'language_zh_cn': '简体中文',
  'language_en_us': 'English',
  'language_ja_jp': '日本語',
  'language_zh_tw': '繁體中文',

  // 登入/認證
  'setup_welcome': '歡迎使用 MeguPaint\n請設定您的使用者名稱和密碼',
  'login_welcome': '歡迎回來，請輸入密碼繼續',
  'select_account_login': '歡迎回來，請選擇帳號登入',
  'username': '使用者名稱',
  'password': '密碼',
  'enter_password': '輸入密碼',
  'confirm_password': '確認密碼',
  'setup_complete': '完成設定',
  'login': '登入',
  'login_hint': '輸入您設定的密碼以繼續',
  'logout': '登出',

  // 多帳號管理
  'add_account': '新增帳號',
  'manage_accounts': '管理帳號',
  'created_at': '建立時間',
  'delete_account': '刪除帳號',
  'confirm_delete_account': '確定要刪除此帳號嗎？此操作無法復原。',
  'delete': '刪除',
  'add': '新增',
  'manage_accounts_hint': '點擊刪除按鈕可移除帳號，至少需要保留一個帳號。',

  // 使用者資訊和私鑰
  'user_logged_in': '已登入',
  'view_private_key': '檢視私鑰',
  'private_key': '私鑰',
  'private_key_warning': '請謹慎保管您的私鑰',
  'private_key_security_warning': '私鑰是您身分的唯一憑證，請勿洩露給他人。洩露私鑰可能導致您的畫作資料被他人存取或竄改。',
  'private_key_value': '私鑰值',
  'copy_private_key': '複製私鑰',
  'private_key_copied': '私鑰已複製到剪貼簿',
  'close': '關閉',

  // 除錯模式
  'pressure_smoothing': '壓感平滑',
  'pressure_smoothing_description': '啟用壓感線性插值以保證平滑',
  'smoothing_factor': '平滑因子',
  'smoothing_factor_description': '值越大平滑越強，但延遲越高',
  'debug_mode': '除錯模式',
  'debug_mode_description': '開啟後在畫布底部顯示除錯資訊',
  'pressure': '壓感',
  'opacity': '透明度',
  'smooth': '平滑',
  'stabilization': '穩定化',

  // 錯誤訊息
  'error_username_empty': '使用者名稱不能為空',
  'error_password_empty': '密碼不能為空',
  'error_password_incorrect': '密碼錯誤',
  'error_password_short': '密碼長度至少6位',
  'error_confirm_password_empty': '請確認密碼',
  'error_password_mismatch': '兩次密碼不一致',
  'error_login_failed': '登入失敗',

  // 繪畫設定
  'drawing_settings': '繪畫設定',
  'settings_brush': '筆刷',
  'settings_color': '顏色',
  'settings_layers': '圖層',
  'settings_advanced': '進階',
  'brush_size': '筆刷大小',
  'brush_stabilization': '穩定度',
  'brush_opacity': '透明度',
  'pressure_sensitivity': '壓感',
  'pressure_sensitivity_desc': '啟用壓感功能（需要裝置支援）',
  'layer_settings_placeholder': '圖層設定功能開發中...',
  'reset_defaults': '還原預設',
  'advanced_settings_desc': '調整線條跟手優化參數，提升繪畫體驗',
  'stroke_optimization': '線條跟手優化',
  'stabilization_desc': '值越大線條越平滑，但跟手性降低',
  'opacity_desc': '筆畫的透明度，1.0 為完全不透明',
  'pressure_intensity': '壓感強度',
  'pressure_intensity_desc': '壓感對線寬的影響程度',
  'feature_toggles': '功能開關',
  'smooth_curve': '平滑曲線',
  'smooth_curve_desc': '使用貝茲曲線平滑筆畫',
  'settings_shortcuts': '快捷鍵',
  'shortcuts_settings_placeholder': '快捷鍵設定功能開發中...',

  // 圖層權限
  'layer_public': '公共圖層',
  'layer_owned': '我的圖層',
  'layer_others': '他人圖層',
  'layer_locked': '已鎖定',
  'layer_unlocked': '未鎖定',
  'layer_visible': '可見',
  'layer_hidden': '隱藏',
  'add_permission': '新增權限',
  'remove_permission': '移除權限',
  'delete_layer': '刪除圖層',
  'error_no_permission': '無權限操作此圖層',
  'error_layer_has_permission': '此圖層已有權限',
  'error_not_your_layer': '只能操作自己的圖層',
  'error_need_login': '請先登入',
  'error_min_layers': '至少需要保留一個圖層',

  // Layer Operations
  'layer_rename': '重新命名',
  'layer_name': '圖層名稱',
  'layer_opacity': '不透明度',
  'layer_move_up': '上移',
  'layer_move_down': '下移',
  'layer_merge_up': '向上合併',
  'layer_merge_down': '向下合併',
  'no_permission': '無權限編輯此圖層',

  // Pressure Curve
  'pressure_enabled': '壓感',
  'pressure_curve': '壓感曲線',
  'pressure_curve_desc': '調整壓感響應曲線，拖曳控制點改變輸出',
  'pressure_test_area': '壓感測試區域',

  // 起筆壓感抬升
  'pressure_start_ramp': '起筆壓感抬升',
  'pressure_start_ramp_description': '起筆時將壓感從 0 逐步抬升，更容易留下筆鋒',
  'pressure_start_ramp_strength': '抬升強度',
  'pressure_start_ramp_strength_description': '值越大抬升過程越長，筆鋒越明顯',
};
