/// 日本語翻訳
const Map<String, String> jaJP = {
  // ホーム
  'app_title': 'MeguPaint',
  'app_subtitle': 'プロフェッショナルペイントソフト',
  'new_canvas': '新しいキャンバス',
  'open_project': 'プロジェクトを開く',
  'recent_projects': '最近のプロジェクト',
  'no_recent_projects': '最近のプロジェクトはありません',

  // 新しいキャンバスダイアログ
  'dialog_new_canvas': '新しいキャンバス',
  'project_name': 'プロジェクト名',
  'untitled_project': '無題のプロジェクト',
  'width': '幅',
  'height': '高さ',
  'cancel': 'キャンセル',
  'confirm': '確認',
  'create': '作成',

  // キャンバスページ
  'undo': '元に戻す',
  'redo': 'やり直し',
  'save': '保存',
  'export': 'エクスポート',

  // ツール
  'tool_brush': 'ブラシ',
  'tool_eraser': '消しゴム',
  'tool_eyedropper': 'スポイト',
  'tool_move': '移動',
  'tool_select': '選択',
  'tool_rectangle': '矩形',
  'tool_circle': '円形',
  'tool_line': '直線',
  'tool_fill': '塗りつぶし',
  'tool_edge_fill': 'エッジ塗り',
  'tool_text': 'テキスト',

  // パネル
  'panel_color': '色',
  'panel_layers': 'レイヤー',
  'new_layer': '新しいレイヤー',
  'background_layer': '背景レイヤー',

  // ステータスバー
  'zoom': 'ズーム',
  'tool': 'ツール',
  'return_home': 'ホームに戻る',

  // キャンバス状態
  'canvas_area': 'キャンバスエリア\n(描画機能は未実装)',
  'canvas_not_loaded': 'キャンバスが読み込まれていません',

  // 設定
  'settings': '設定',
  'language': '言語',
  'language_zh_cn': '简体中文',
  'language_en_us': 'English',
  'language_ja_jp': '日本語',
  'language_zh_tw': '繁體中文',

  // ログイン/認証
  'setup_welcome': 'MeguPaintへようこそ\nユーザー名とパスワードを設定してください',
  'login_welcome': 'おかえりなさい、パスワードを入力してください',
  'select_account_login': 'おかえりなさい、アカウントを選択してログインしてください',
  'username': 'ユーザー名',
  'password': 'パスワード',
  'enter_password': 'パスワードを入力',
  'confirm_password': 'パスワード確認',
  'setup_complete': '設定完了',
  'login': 'ログイン',
  'login_hint': '続行するにはパスワードを入力してください',
  'logout': 'ログアウト',

  // マルチアカウント管理
  'add_account': 'アカウント追加',
  'manage_accounts': 'アカウント管理',
  'created_at': '作成日',
  'delete_account': 'アカウント削除',
  'confirm_delete_account': 'このアカウントを削除してもよろしいですか？この操作は取り消せません。',
  'delete': '削除',
  'add': '追加',
  'manage_accounts_hint': '削除ボタンをクリックしてアカウントを削除できます。最低1つのアカウントが必要です。',

  // ユーザー情報と秘密鍵
  'user_logged_in': 'ログイン中',
  'view_private_key': '秘密鍵を表示',
  'private_key': '秘密鍵',
  'private_key_warning': '秘密鍵を安全に保管してください',
  'private_key_security_warning':
      '秘密鍵はあなたの身元を証明する唯一の資格情報です。他者と共有しないでください。秘密鍵が漏洩すると、あなたの作品データが他者によってアクセスや改ざんされる可能性があります。',
  'private_key_value': '秘密鍵の値',
  'copy_private_key': '秘密鍵をコピー',
  'private_key_copied': '秘密鍵をクリップボードにコピーしました',
  'close': '閉じる',

  // デバッグモード
  'pressure_smoothing': '圧感平滑',
  'pressure_smoothing_description': '圧感線形補間を有効にして滑らかにする',
  'smoothing_factor': '平滑因子',
  'smoothing_factor_description': '値が大きいほど滑らかですが、遅延が増えます',
  'debug_mode': 'デバッグモード',
  'debug_mode_description': '有効にするとキャンバスの下部にデバッグ情報が表示されます',
  'pressure': '圧感',
  'opacity': '透明度',
  'smooth': '平滑',
  'stabilization': '安定化',

  // エラーメッセージ
  'error_username_empty': 'ユーザー名を入力してください',
  'error_password_empty': 'パスワードを入力してください',
  'error_password_incorrect': 'パスワードが正しくありません',
  'error_password_short': 'パスワードは6文字以上必要です',
  'error_confirm_password_empty': 'パスワードを確認してください',
  'error_password_mismatch': 'パスワードが一致しません',
  'error_login_failed': 'ログインに失敗しました',

  // 描画設定
  'drawing_settings': '描画設定',
  'settings_brush': 'ブラシ',
  'settings_color': 'カラー',
  'settings_layers': 'レイヤー',
  'settings_advanced': '詳細',
  'brush_size': 'ブラシサイズ',
  'brush_stabilization': '安定化',
  'brush_opacity': '不透明度',
  'pressure_sensitivity': '筆圧感度',
  'pressure_sensitivity_desc': '筆圧機能を有効にする（デバイス対応必要）',
  'layer_settings_placeholder': 'レイヤー設定は開発中...',
  'reset_defaults': 'デフォルトに戻す',
  'advanced_settings_desc': 'ストローク最適化パラメータで描画体験を向上',
  'stroke_optimization': 'ストローク最適化',
  'stabilization_desc': '値が大きいほど滑らかだが、追従性が低下',
  'opacity_desc': 'ストロークの不透明度、1.0で完全不透明',
  'pressure_intensity': '筆圧強度',
  'pressure_intensity_desc': '筆圧が線幅に与える影響度',
  'feature_toggles': '機能切り替え',
  'smooth_curve': 'スムーズカーブ',
  'smooth_curve_desc': 'ベジェ曲線でストロークを滑らかに',
  'settings_shortcuts': 'ショートカット',
  'shortcuts_settings_placeholder': 'ショートカット設定は開発中...',

  // レイヤー権限
  'layer_public': 'パブリックレイヤー',
  'layer_owned': 'マイレイヤー',
  'layer_others': '他人のレイヤー',
  'layer_locked': 'ロック済み',
  'layer_unlocked': 'ロック解除',
  'layer_visible': '表示',
  'layer_hidden': '非表示',
  'add_permission': '権限追加',
  'remove_permission': '権限削除',
  'delete_layer': 'レイヤー削除',
  'error_no_permission': 'このレイヤーを編集する権限がありません',
  'error_layer_has_permission': 'このレイヤーには既に権限があります',
  'error_not_your_layer': '自分のレイヤーのみ編集できます',
  'error_need_login': 'ログインしてください',
  'error_min_layers': '最低1つのレイヤーが必要です',

  // Layer Operations
  'layer_rename': '名前変更',
  'layer_name': 'レイヤー名',
  'layer_opacity': '不透明度',
  'layer_move_up': '上に移動',
  'layer_move_down': '下に移動',
  'layer_merge_up': '上に結合',
  'layer_merge_down': '下に結合',
  'no_permission': 'このレイヤーを編集する権限がありません',

  // Pressure Curve
  'pressure_enabled': '筆圧',
  'pressure_curve': '筆圧カーブ',
  'pressure_curve_desc': '筆圧レスポンスカーブを調整、コントロールポイントをドラッグして出力を変更',
  'pressure_test_area': '筆圧テストエリア',

  // Pressure Start Ramp
  'pressure_start_ramp': '起筆の筆圧ランプ',
  'pressure_start_ramp_description': 'ストローク開始時に筆圧を 0 から徐々に上げ、筆先を出しやすくします',
  'pressure_start_ramp_strength': 'ランプ強度',
  'pressure_start_ramp_strength_description': '値が大きいほどランプが長く、筆先が強調されます',
};
