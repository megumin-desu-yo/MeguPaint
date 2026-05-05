/// English translations
const Map<String, String> enUS = {
  // Home
  'app_title': 'MeguPaint',
  'app_subtitle': 'Professional Painting Software',
  'new_canvas': 'New Canvas',
  'open_project': 'Open Project',
  'recent_projects': 'Recent Projects',
  'no_recent_projects': 'No recent projects',

  // New Canvas Dialog
  'dialog_new_canvas': 'New Canvas',
  'project_name': 'Project Name',
  'untitled_project': 'Untitled Project',
  'width': 'Width',
  'height': 'Height',
  'cancel': 'Cancel',
  'confirm': 'Confirm',
  'create': 'Create',

  // Canvas Page
  'undo': 'Undo',
  'redo': 'Redo',
  'save': 'Save',
  'export': 'Export',

  // Tools
  'tool_brush': 'Brush',
  'tool_eraser': 'Eraser',
  'tool_eyedropper': 'Eyedropper',
  'tool_move': 'Move',
  'tool_select': 'Select',
  'tool_rectangle': 'Rectangle',
  'tool_circle': 'Circle',
  'tool_line': 'Line',
  'tool_fill': 'Fill',
  'tool_edge_fill': 'Edge Fill',
  'tool_text': 'Text',

  // Panels
  'panel_color': 'Color',
  'panel_layers': 'Layers',
  'new_layer': 'New Layer',
  'background_layer': 'Background Layer',

  // Status Bar
  'zoom': 'Zoom',
  'tool': 'Tool',
  'return_home': 'Return Home',

  // Canvas State
  'canvas_area': 'Canvas Area\n(Drawing feature pending)',
  'canvas_not_loaded': 'Canvas not loaded',

  // Settings
  'settings': 'Settings',
  'language': 'Language',
  'language_zh_cn': '简体中文',
  'language_en_us': 'English',
  'language_ja_jp': '日本語',
  'language_zh_tw': '繁體中文',

  // Login/Auth
  'setup_welcome':
      'Welcome to MeguPaint\nPlease set your username and password',
  'login_welcome': 'Welcome back, please enter your password',
  'select_account_login': 'Welcome back, please select an account to login',
  'username': 'Username',
  'password': 'Password',
  'enter_password': 'Enter Password',
  'confirm_password': 'Confirm Password',
  'setup_complete': 'Complete Setup',
  'login': 'Login',
  'login_hint': 'Enter your password to continue',
  'logout': 'Logout',

  // Multi-account Management
  'add_account': 'Add Account',
  'manage_accounts': 'Manage Accounts',
  'created_at': 'Created',
  'delete_account': 'Delete Account',
  'confirm_delete_account':
      'Are you sure you want to delete this account? This action cannot be undone.',
  'delete': 'Delete',
  'add': 'Add',
  'manage_accounts_hint':
      'Click the delete button to remove an account. At least one account must be kept.',

  // User Info and Private Key
  'user_logged_in': 'Logged In',
  'view_private_key': 'View Private Key',
  'private_key': 'Private Key',
  'private_key_warning': 'Please keep your private key secure',
  'private_key_security_warning':
      'The private key is the unique credential for your identity. Do not share it with others. Leaking your private key may allow others to access or tamper with your artwork data.',
  'private_key_value': 'Private Key Value',
  'copy_private_key': 'Copy Private Key',
  'private_key_copied': 'Private key copied to clipboard',
  'close': 'Close',

  // Debug Mode
  'pressure_smoothing': 'Pressure Smoothing',
  'pressure_smoothing_description':
      'Enable pressure linear interpolation for smoothness',
  'smoothing_factor': 'Smoothing Factor',
  'smoothing_factor_description': 'Higher value means smoother but more delay',
  'debug_mode': 'Debug Mode',
  'debug_mode_description': 'Enable debug information display',
  'pressure': 'Pressure',
  'opacity': 'Opacity',
  'smooth': 'Smooth',
  'stabilization': 'Stabilization',

  // Error Messages
  'error_username_empty': 'Username cannot be empty',
  'error_password_empty': 'Password cannot be empty',
  'error_password_incorrect': 'Incorrect password',
  'error_password_short': 'Password must be at least 6 characters',
  'error_confirm_password_empty': 'Please confirm your password',
  'error_password_mismatch': 'Passwords do not match',
  'error_login_failed': 'Login failed',

  // Drawing Settings
  'drawing_settings': 'Drawing Settings',
  'settings_brush': 'Brush',
  'settings_color': 'Color',
  'settings_layers': 'Layers',
  'settings_advanced': 'Advanced',
  'brush_size': 'Brush Size',
  'brush_stabilization': 'Stabilization',
  'brush_opacity': 'Opacity',
  'pressure_sensitivity': 'Pressure Sensitivity',
  'pressure_sensitivity_desc':
      'Enable pressure sensitivity (requires device support)',
  'layer_settings_placeholder': 'Layer settings in development...',
  'reset_defaults': 'Reset Defaults',
  'advanced_settings_desc':
      'Adjust stroke optimization parameters for better drawing experience',
  'stroke_optimization': 'Stroke Optimization',
  'stabilization_desc': 'Higher value = smoother lines but less responsive',
  'opacity_desc': 'Stroke opacity, 1.0 = fully opaque',
  'pressure_intensity': 'Pressure Intensity',
  'pressure_intensity_desc': 'How much pressure affects line width',
  'feature_toggles': 'Feature Toggles',
  'smooth_curve': 'Smooth Curve',
  'smooth_curve_desc': 'Use Bezier curves to smooth strokes',
  'settings_shortcuts': 'Shortcuts',
  'shortcuts_settings_placeholder': 'Shortcuts settings in development...',

  // Layer Permissions
  'layer_public': 'Public Layer',
  'layer_owned': 'My Layer',
  'layer_others': "Others' Layer",
  'layer_locked': 'Locked',
  'layer_unlocked': 'Unlocked',
  'layer_visible': 'Visible',
  'layer_hidden': 'Hidden',
  'add_permission': 'Add Permission',
  'remove_permission': 'Remove Permission',
  'delete_layer': 'Delete Layer',
  'error_no_permission': 'No permission to modify this layer',
  'error_layer_has_permission': 'This layer already has permission',
  'error_not_your_layer': 'Can only modify your own layers',
  'error_need_login': 'Please login first',
  'error_min_layers': 'Must keep at least one layer',

  // Layer Operations
  'layer_rename': 'Rename',
  'layer_name': 'Layer Name',
  'layer_opacity': 'Opacity',
  'layer_move_up': 'Move Up',
  'layer_move_down': 'Move Down',
  'layer_merge_up': 'Merge Up',
  'layer_merge_down': 'Merge Down',
  'no_permission': 'No permission to edit this layer',

  // Pressure Curve
  'pressure_enabled': 'Pressure',
  'pressure_curve': 'Pressure Curve',
  'pressure_curve_desc':
      'Adjust pressure response curve, drag control points to change output',
  'pressure_test_area': 'Pressure Test Area',

  // Pressure Start Ramp
  'pressure_start_ramp': 'Pressure Start Ramp',
  'pressure_start_ramp_description':
      'Ramp pressure up from 0 at stroke start to create a sharper nib',
  'pressure_start_ramp_strength': 'Ramp Strength',
  'pressure_start_ramp_strength_description':
      'Higher value makes the ramp longer and the nib more visible',
};
