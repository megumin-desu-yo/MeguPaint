/// 简体中文翻译
const Map<String, String> zhCN = {
  // 主页
  'app_title': 'MeguPaint',
  'app_subtitle': '专业绘画软件',
  'new_canvas': '新建画布',
  'open_project': '打开项目',
  'recent_projects': '最近项目',
  'no_recent_projects': '暂无最近项目',

  // 新建画布对话框
  'dialog_new_canvas': '新建画布',
  'project_name': '项目名称',
  'untitled_project': '未命名项目',
  'width': '宽度',
  'height': '高度',
  'cancel': '取消',
  'confirm': '确认',
  'create': '创建',

  // 画布页面
  'undo': '撤销',
  'redo': '重做',
  'save': '保存',
  'export': '导出',

  // 工具
  'tool_brush': '画笔',
  'tool_eraser': '橡皮擦',
  'tool_eyedropper': '吸色器',
  'tool_move': '移动',
  'tool_select': '选择',
  'tool_rectangle': '矩形',
  'tool_circle': '圆形',
  'tool_line': '直线',
  'tool_fill': '填充',
  'tool_edge_fill': '边缘填充',
  'tool_text': '文字',

  // 面板
  'panel_color': '颜色',
  'panel_layers': '图层',
  'new_layer': '新建图层',
  'background_layer': '背景图层',

  // 状态栏
  'zoom': '缩放',
  'tool': '工具',
  'return_home': '返回主页',

  // 画布状态
  'canvas_area': '画布区域\n(待实现绘图功能)',
  'canvas_not_loaded': '未加载画布',

  // 设置
  'settings': '设置',
  'language': '语言',
  'language_zh_cn': '简体中文',
  'language_en_us': 'English',
  'language_ja_jp': '日本語',
  'language_zh_tw': '繁體中文',

  // 登录/认证
  'setup_welcome': '欢迎使用 MeguPaint\n请设置您的用户名和密码',
  'login_welcome': '欢迎回来，请输入密码继续',
  'select_account_login': '欢迎回来，请选择账号登录',
  'username': '用户名',
  'password': '密码',
  'enter_password': '输入密码',
  'confirm_password': '确认密码',
  'setup_complete': '完成设置',
  'login': '登录',
  'login_hint': '输入您设置的密码以继续',
  'logout': '退出登录',

  // 多账号管理
  'add_account': '添加账号',
  'manage_accounts': '管理账号',
  'created_at': '创建时间',
  'delete_account': '删除账号',
  'confirm_delete_account': '确定要删除此账号吗？此操作不可撤销。',
  'delete': '删除',
  'add': '添加',
  'manage_accounts_hint': '点击删除按钮可移除账号，至少需要保留一个账号。',

  // 用户信息和私钥
  'user_logged_in': '已登录',
  'view_private_key': '查看私钥',
  'private_key': '私钥',
  'private_key_warning': '请谨慎保管您的私钥',
  'private_key_security_warning': '私钥是您身份的唯一凭证，请勿泄露给他人。泄露私钥可能导致您的画作数据被他人访问或篡改。',
  'private_key_value': '私钥值',
  'copy_private_key': '复制私钥',
  'private_key_copied': '私钥已复制到剪贴板',
  'close': '关闭',

  // 调试模式
  'pressure_smoothing': '压感平滑',
  'pressure_smoothing_description': '启用压感线性插值以保证平滑',
  'smoothing_factor': '平滑因子',
  'smoothing_factor_description': '值越大平滑越强，但延迟越高',
  'debug_mode': '调试模式',
  'debug_mode_description': '启用调试信息显示',
  'pressure': '压感',
  'opacity': '透明度',
  'smooth': '平滑',
  'stabilization': '稳定化',

  // 错误消息
  'error_username_empty': '用户名不能为空',
  'error_password_empty': '密码不能为空',
  'error_password_incorrect': '密码错误',
  'error_password_short': '密码长度至少6位',
  'error_confirm_password_empty': '请确认密码',
  'error_password_mismatch': '两次密码不一致',
  'error_login_failed': '登录失败',

  // 绘画设置
  'drawing_settings': '绘画设置',
  'settings_brush': '笔刷',
  'settings_color': '颜色',
  'settings_layers': '图层',
  'settings_advanced': '高级',
  'brush_size': '笔刷大小',
  'brush_stabilization': '稳定度',
  'brush_opacity': '透明度',
  'pressure_sensitivity': '压感',
  'pressure_sensitivity_desc': '启用压感功能（需要设备支持）',
  'layer_settings_placeholder': '图层设置功能开发中...',
  'reset_defaults': '还原默认',
  'advanced_settings_desc': '调整线条跟手优化参数，提升绘画体验',
  'stroke_optimization': '线条跟手优化',
  'stabilization_desc': '值越大线条越平滑，但跟手性降低',
  'opacity_desc': '笔画的透明度，1.0 为完全不透明',
  'pressure_intensity': '压感强度',
  'pressure_intensity_desc': '压感对线宽的影响程度',
  'feature_toggles': '功能开关',
  'smooth_curve': '平滑曲线',
  'smooth_curve_desc': '使用贝塞尔曲线平滑笔画',
  'settings_shortcuts': '快捷键',
  'shortcuts_settings_placeholder': '快捷键设置功能开发中...',

  // 图层权限
  'layer_public': '公共图层',
  'layer_owned': '我的图层',
  'layer_others': '他人图层',
  'layer_locked': '已锁定',
  'layer_unlocked': '未锁定',
  'layer_visible': '可见',
  'layer_hidden': '隐藏',
  'add_permission': '添加权限',
  'remove_permission': '移除权限',
  'delete_layer': '删除图层',
  'error_no_permission': '无权限操作此图层',
  'error_layer_has_permission': '此图层已有权限',
  'error_not_your_layer': '只能操作自己的图层',
  'error_need_login': '请先登录',
  'error_min_layers': '至少需要保留一个图层',

  // 图层操作
  'layer_rename': '重命名',
  'layer_name': '图层名称',
  'layer_opacity': '不透明度',
  'layer_move_up': '上移',
  'layer_move_down': '下移',
  'layer_merge_up': '向上合并',
  'layer_merge_down': '向下合并',
  'no_permission': '无权限编辑此图层',

  // 压感曲线
  'pressure_enabled': '压感',
  'pressure_curve': '压感曲线',
  'pressure_curve_desc': '调整压感响应曲线，拖动控制点改变输出',
  'pressure_test_area': '压感测试区域',

  // 起笔压感抬升
  'pressure_start_ramp': '起笔压感抬升',
  'pressure_start_ramp_description': '起笔时将压感从 0 逐步抬升，更容易留下笔锋',
  'pressure_start_ramp_strength': '抬升强度',
  'pressure_start_ramp_strength_description': '值越大抬升过程越长，笔锋越明显',
};
