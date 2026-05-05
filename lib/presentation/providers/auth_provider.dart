import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../domain/entities/user_credential.dart';
import '../../domain/services/crypto_service.dart';
import '../../data/services/crypto_service_impl.dart';

/// 认证状态
class AuthState {
  /// 是否已初始化
  final bool isInitialized;

  /// 是否已登录
  final bool isLoggedIn;

  /// 当前用户凭证
  final UserCredential? credential;

  /// 错误消息
  final String? errorMessage;

  /// 是否是首次使用 (无凭证)
  final bool isFirstTime;

  /// 所有账号列表
  final List<UserCredential> allAccounts;

  /// 当前选中的账号索引 (用于登录)
  final int selectedAccountIndex;

  const AuthState({
    this.isInitialized = false,
    this.isLoggedIn = false,
    this.credential,
    this.errorMessage,
    this.isFirstTime = true,
    this.allAccounts = const [],
    this.selectedAccountIndex = 0,
  });

  /// 当前用户名
  String get username => credential?.username ?? '';

  /// 当前私钥
  String get privateKey => credential?.privateKey ?? '';

  /// 账号数量
  int get accountCount => allAccounts.length;

  /// 当前选中的账号
  UserCredential? get selectedAccount =>
      allAccounts.isNotEmpty && selectedAccountIndex < allAccounts.length
      ? allAccounts[selectedAccountIndex]
      : null;

  /// 复制并修改
  AuthState copyWith({
    bool? isInitialized,
    bool? isLoggedIn,
    UserCredential? credential,
    String? errorMessage,
    bool? isFirstTime,
    List<UserCredential>? allAccounts,
    int? selectedAccountIndex,
    bool clearError = false,
    bool clearCredential = false,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      credential: clearCredential ? null : (credential ?? this.credential),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isFirstTime: isFirstTime ?? this.isFirstTime,
      allAccounts: allAccounts ?? this.allAccounts,
      selectedAccountIndex: selectedAccountIndex ?? this.selectedAccountIndex,
    );
  }
}

/// 认证状态管理器
class AuthNotifier extends StateNotifier<AuthState> {
  final CryptoService _cryptoService;

  /// Hive box 名称
  static const String _boxName = 'auth';
  static const String _replayBoxName = 'replays';

  /// 账号列表存储键
  static const String _accountsKey = 'accounts';

  AuthNotifier({CryptoService? cryptoService})
    : _cryptoService = cryptoService ?? CryptoServiceImpl(),
      super(const AuthState()) {
    _init();
  }

  /// 保存复盘数据到本地
  Future<void> saveReplay(List<Map<String, dynamic>> replayData) async {
    try {
      final box = await Hive.openBox(_replayBoxName);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final record = {
        'id': timestamp.toString(),
        'timestamp': timestamp,
        'data': replayData,
      };

      final List<dynamic> history = box.get('history', defaultValue: []);
      final updatedHistory = List<dynamic>.from(history)..insert(0, record);

      // 最多保存 50 场复盘
      if (updatedHistory.length > 50) {
        updatedHistory.removeRange(50, updatedHistory.length);
      }

      await box.put('history', updatedHistory);
    } catch (e) {
      print('保存复盘失败: $e');
    }
  }

  /// 验证密码（不改变登录状态）
  bool verifyPassword(String password) {
    if (password.isEmpty) return false;

    final credential = state.credential;
    if (credential == null) return false;

    final passwordHash = _cryptoService.hashPassword(
      password,
      credential.username,
    );
    return passwordHash == credential.passwordHash;
  }

  /// 初始化 - 加载所有账号
  Future<void> _init() async {
    try {
      final box = await Hive.openBox(_boxName);
      final accountsJson = box.get(_accountsKey);

      if (accountsJson != null && accountsJson is List) {
        // 加载所有账号
        final accounts = accountsJson
            .map((e) => UserCredential.fromMap(Map<String, dynamic>.from(e)))
            .toList();

        if (accounts.isNotEmpty) {
          state = AuthState(
            isInitialized: true,
            isLoggedIn: false,
            allAccounts: accounts,
            selectedAccountIndex: 0,
            isFirstTime: false,
          );
        } else {
          // 无账号，首次使用
          state = const AuthState(
            isInitialized: true,
            isLoggedIn: false,
            isFirstTime: true,
          );
        }
      } else {
        // 首次使用，需要设置凭证
        state = const AuthState(
          isInitialized: true,
          isLoggedIn: false,
          isFirstTime: true,
        );
      }
    } catch (e) {
      state = AuthState(isInitialized: true, errorMessage: '初始化失败: $e');
    }
  }

  /// 保存所有账号到 Hive
  Future<void> _saveAccounts(List<UserCredential> accounts) async {
    final box = await Hive.openBox(_boxName);
    await box.put(_accountsKey, accounts.map((e) => e.toMap()).toList());
  }

  /// 添加新账号
  Future<bool> addAccount({
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    // 验证输入
    if (username.isEmpty) {
      state = state.copyWith(errorMessage: '用户名不能为空', clearError: false);
      return false;
    }

    if (password.isEmpty) {
      state = state.copyWith(errorMessage: '密码不能为空', clearError: false);
      return false;
    }

    if (password != confirmPassword) {
      state = state.copyWith(errorMessage: '两次密码不一致', clearError: false);
      return false;
    }

    if (password.length < 6) {
      state = state.copyWith(errorMessage: '密码长度至少6位', clearError: false);
      return false;
    }

    // 检查用户名是否已存在
    if (state.allAccounts.any((a) => a.username == username)) {
      state = state.copyWith(errorMessage: '用户名已存在', clearError: false);
      return false;
    }

    try {
      // 派生私钥
      final privateKey = _cryptoService.derivePrivateKey(username, password);

      // 哈希密码
      final passwordHash = _cryptoService.hashPassword(password, username);

      // 创建凭证
      final credential = UserCredential(
        username: username,
        passwordHash: passwordHash,
        privateKey: privateKey,
        createdAt: DateTime.now(),
      );

      // 添加到账号列表
      final newAccounts = [...state.allAccounts, credential];
      await _saveAccounts(newAccounts);

      // 更新状态
      state = state.copyWith(
        allAccounts: newAccounts,
        selectedAccountIndex: newAccounts.length - 1,
        isFirstTime: false,
        clearError: true,
      );

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: '添加账号失败: $e', clearError: false);
      return false;
    }
  }

  /// 切换选中的账号
  void selectAccount(int index) {
    if (index >= 0 && index < state.allAccounts.length) {
      state = state.copyWith(selectedAccountIndex: index, clearError: true);
    }
  }

  /// 删除账号
  Future<bool> deleteAccount(int index) async {
    if (index < 0 || index >= state.allAccounts.length) {
      state = state.copyWith(errorMessage: '无效的账号索引', clearError: false);
      return false;
    }

    // 至少保留一个账号
    if (state.allAccounts.length <= 1) {
      state = state.copyWith(errorMessage: '至少需要保留一个账号', clearError: false);
      return false;
    }

    try {
      final newAccounts = List<UserCredential>.from(state.allAccounts);
      newAccounts.removeAt(index);
      await _saveAccounts(newAccounts);

      // 调整选中索引
      int newIndex = state.selectedAccountIndex;
      if (newIndex >= newAccounts.length) {
        newIndex = newAccounts.length - 1;
      } else if (index < newIndex) {
        newIndex--;
      }

      state = state.copyWith(
        allAccounts: newAccounts,
        selectedAccountIndex: newIndex,
        clearError: true,
      );

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: '删除账号失败: $e', clearError: false);
      return false;
    }
  }

  /// 设置凭证 (首次使用) - 注册后自动登录
  Future<bool> setupCredential({
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    final success = await addAccount(
      username: username,
      password: password,
      confirmPassword: confirmPassword,
    );

    // 注册成功后自动登录
    if (success) {
      return login(password);
    }
    return false;
  }

  /// 登录验证
  Future<bool> login(String password) async {
    final selectedAccount = state.selectedAccount;
    if (selectedAccount == null) {
      state = state.copyWith(errorMessage: '请选择账号', clearError: false);
      return false;
    }

    if (password.isEmpty) {
      state = state.copyWith(errorMessage: '密码不能为空', clearError: false);
      return false;
    }

    try {
      // 验证密码
      final passwordHash = _cryptoService.hashPassword(
        password,
        selectedAccount.username,
      );

      if (passwordHash != selectedAccount.passwordHash) {
        state = state.copyWith(errorMessage: '密码错误', clearError: false);
        return false;
      }

      // 重新派生私钥 (私钥不存储，每次登录重新生成)
      final privateKey = _cryptoService.derivePrivateKey(
        selectedAccount.username,
        password,
      );

      // 更新凭证中的私钥
      final credential = selectedAccount.copyWith(privateKey: privateKey);

      // 更新状态
      state = state.copyWith(
        isLoggedIn: true,
        credential: credential,
        clearError: true,
      );

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: '登录失败: $e', clearError: false);
      return false;
    }
  }

  /// 登出
  Future<void> logout() async {
    state = state.copyWith(
      isLoggedIn: false,
      clearCredential: true,
      clearError: true,
    );
  }

  /// 清除错误消息
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// 认证 Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
