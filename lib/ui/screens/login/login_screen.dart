import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../l10n/app_localizations.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../home/home_screen.dart';
import '../../widgets/app_toast.dart';

/// 登录屏幕 - 首次设置或登录验证
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // 表单控制器
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // 表单键
  final _formKey = GlobalKey<FormState>();

  // 是否显示密码
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // 是否正在加载
  bool _isLoading = false;

  // 记住密码
  bool _rememberPassword = false;

  // Hive box 键
  static const String _authBoxName = 'auth';
  static const String _rememberKey = 'remember_password';
  static const String _savedPasswordKey = 'saved_password';

  // 是否处于添加账号模式
  bool _isAddingAccount = false;

  // 是否处于管理模式
  bool _isManagingAccounts = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedPassword();
  }

  Future<void> _loadRememberedPassword() async {
    final box = await Hive.openBox(_authBoxName);
    final remember = box.get(_rememberKey, defaultValue: false) as bool;
    final saved = box.get(_savedPasswordKey, defaultValue: '') as String;
    if (remember && saved.isNotEmpty) {
      setState(() {
        _rememberPassword = true;
        _passwordController.text = saved;
      });
    }
  }

  Future<void> _saveRememberedPassword(String password) async {
    final box = await Hive.openBox(_authBoxName);
    if (_rememberPassword) {
      await box.put(_rememberKey, true);
      await box.put(_savedPasswordKey, password);
    } else {
      await box.put(_rememberKey, false);
      await box.delete(_savedPasswordKey);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final l10n = AppLocalizations.of(context);

    // 如果已登录，跳转到主页
    if (authState.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      });
    }

    // 监听错误消息
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage!.isNotEmpty) {
        toast.error(context, next.errorMessage!);
        ref.read(authProvider.notifier).clearError();
      }
    });

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _isManagingAccounts
                ? _buildManageAccountsView(authState, l10n)
                : _isAddingAccount
                ? _buildAddAccountView(authState, l10n)
                : _buildMainView(authState, l10n),
          ),
        ),
      ),
    );
  }

  /// 主视图：账号列表或首次设置
  Widget _buildMainView(AuthState authState, AppLocalizations l10n) {
    // 首次使用：显示设置表单
    if (authState.isFirstTime) {
      return _buildFirstTimeView(authState, l10n);
    }

    // 有账号：显示账号列表
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo
          Icon(
            Icons.palette,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),

          // 标题
          Text(
            'MeguPaint',
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // 副标题
          Text(
            l10n.translate('select_account_login'),
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // 账号列表
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: authState.accountCount,
              itemBuilder: (context, index) {
                final account = authState.allAccounts[index];
                final isSelected = index == authState.selectedAccountIndex;

                return Card(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        account.username[0].toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(account.username),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    selected: isSelected,
                    onTap: () {
                      ref.read(authProvider.notifier).selectAccount(index);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 密码输入
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: l10n.translate('enter_password'),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: const OutlineInputBorder(),
            ),
            obscureText: _obscurePassword,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.translate('error_password_empty');
              }
              return null;
            },
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleLogin(),
          ),
          // 记住密码
          CheckboxListTile(
            value: _rememberPassword,
            onChanged: (value) {
              setState(() {
                _rememberPassword = value ?? false;
              });
            },
            title: const Text('记住密码'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          const SizedBox(height: 8),

          // 登录按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      l10n.translate('login'),
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // 底部按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l10n.translate('add_account')),
                onPressed: () {
                  setState(() {
                    _isAddingAccount = true;
                    _usernameController.clear();
                    _passwordController.clear();
                    _confirmPasswordController.clear();
                  });
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.settings),
                label: Text(l10n.translate('manage_accounts')),
                onPressed: () {
                  setState(() {
                    _isManagingAccounts = true;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 首次使用视图
  Widget _buildFirstTimeView(AuthState authState, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo
          Icon(
            Icons.palette,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),

          // 标题
          Text(
            'MeguPaint',
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // 副标题
          Text(
            l10n.translate('setup_welcome'),
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // 用户名输入
          TextFormField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: l10n.translate('username'),
              prefixIcon: const Icon(Icons.person),
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.translate('error_username_empty');
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // 密码输入
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: l10n.translate('password'),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: const OutlineInputBorder(),
            ),
            obscureText: _obscurePassword,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.translate('error_password_empty');
              }
              if (value.length < 6) {
                return l10n.translate('error_password_short');
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // 确认密码
          TextFormField(
            controller: _confirmPasswordController,
            decoration: InputDecoration(
              labelText: l10n.translate('confirm_password'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
              border: const OutlineInputBorder(),
            ),
            obscureText: _obscureConfirmPassword,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.translate('error_confirm_password_empty');
              }
              if (value != _passwordController.text) {
                return l10n.translate('error_password_mismatch');
              }
              return null;
            },
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleSetup(),
          ),
          const SizedBox(height: 24),

          // 提交按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSetup,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      l10n.translate('setup_complete'),
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 添加账号视图
  Widget _buildAddAccountView(AuthState authState, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 标题
          Text(
            l10n.translate('add_account'),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),

          // 用户名输入
          TextFormField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: l10n.translate('username'),
              prefixIcon: const Icon(Icons.person),
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.translate('error_username_empty');
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // 密码输入
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: l10n.translate('password'),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: const OutlineInputBorder(),
            ),
            obscureText: _obscurePassword,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.translate('error_password_empty');
              }
              if (value.length < 6) {
                return l10n.translate('error_password_short');
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // 确认密码
          TextFormField(
            controller: _confirmPasswordController,
            decoration: InputDecoration(
              labelText: l10n.translate('confirm_password'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
              border: const OutlineInputBorder(),
            ),
            obscureText: _obscureConfirmPassword,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.translate('error_confirm_password_empty');
              }
              if (value != _passwordController.text) {
                return l10n.translate('error_password_mismatch');
              }
              return null;
            },
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleAddAccount(),
          ),
          const SizedBox(height: 24),

          // 按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isAddingAccount = false;
                    });
                  },
                  child: Text(l10n.translate('cancel')),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleAddAccount,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.translate('add')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 管理账号视图
  Widget _buildManageAccountsView(AuthState authState, AppLocalizations l10n) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 标题
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _isManagingAccounts = false;
                });
              },
            ),
            Expanded(
              child: Text(
                l10n.translate('manage_accounts'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48), // 平衡返回按钮
          ],
        ),
        const SizedBox(height: 24),

        // 账号列表
        Expanded(
          child: ListView.builder(
            itemCount: authState.accountCount,
            itemBuilder: (context, index) {
              final account = authState.allAccounts[index];

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      account.username[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(account.username),
                  subtitle: Text(
                    '${l10n.translate('created_at')}: ${_formatDate(account.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: authState.accountCount > 1
                      ? IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _confirmDeleteAccount(index, l10n),
                        )
                      : null,
                ),
              );
            },
          ),
        ),

        // 底部提示
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.translate('manage_accounts_hint'),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 确认删除账号
  void _confirmDeleteAccount(int index, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('delete_account')),
        content: Text(l10n.translate('confirm_delete_account')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).deleteAccount(index);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.translate('delete')),
          ),
        ],
      ),
    );
  }

  /// 处理首次设置
  Future<void> _handleSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await ref
        .read(authProvider.notifier)
        .setupCredential(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          confirmPassword: _confirmPasswordController.text,
        );

    if (mounted) {
      setState(() => _isLoading = false);

      if (success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  /// 处理登录
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final password = _passwordController.text;
    final success = await ref.read(authProvider.notifier).login(password);

    if (mounted) {
      setState(() => _isLoading = false);

      if (success) {
        await _saveRememberedPassword(password);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  /// 处理添加账号
  Future<void> _handleAddAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await ref
        .read(authProvider.notifier)
        .addAccount(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          confirmPassword: _confirmPasswordController.text,
        );

    if (mounted) {
      setState(() => _isLoading = false);

      if (success) {
        setState(() {
          _isAddingAccount = false;
        });
        toast.success(context, '账号添加成功');
      }
    }
  }
}
