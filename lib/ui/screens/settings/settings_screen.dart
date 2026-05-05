import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/utils/identity_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/providers/settings_provider.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../widgets/app_toast.dart';

/// 设置页面
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final authState = ref.watch(authProvider);
    final l10n = AppLocalizations.of(context);

    String? fingerprint;
    if (authState.isLoggedIn && authState.privateKey.isNotEmpty) {
      try {
        fingerprint = IdentityUtils.getUserFingerprintFromPrivateKey(
          authState.privateKey,
          bytes: 8,
        );
      } catch (_) {
        fingerprint = null;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('settings'))),
      body: ListView(
        children: [
          // 用户信息卡片
          if (authState.isLoggedIn) ...[
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          child: Text(
                            authState.username[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                authState.username,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (fingerprint != null)
                                Text(
                                  '${authState.username}#$fingerprint',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              Text(
                                l10n.translate('user_logged_in'),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(),
                    const SizedBox(height: 8),
                    // 私钥查看按钮
                    ListTile(
                      leading: const Icon(Icons.key),
                      title: Text(l10n.translate('view_private_key')),
                      subtitle: Text(l10n.translate('private_key_warning')),
                      trailing: const Icon(Icons.visibility),
                      onTap: () =>
                          _showPrivateKeyPasswordDialog(context, ref, l10n),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 语言设置
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.translate('language')),
            subtitle: Text(_getLanguageName(settings.currentLocale.toString())),
            onTap: () => _showLanguageDialog(context, ref, l10n),
          ),

          // 调试模式设置
          SwitchListTile(
            secondary: const Icon(Icons.bug_report),
            title: Text(l10n.translate('debug_mode')),
            subtitle: Text(l10n.translate('debug_mode_description')),
            value: settings.debugMode,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setDebugMode(value);
            },
          ),
        ],
      ),
    );
  }

  /// 显示私钥查看前的密码验证对话框
  void _showPrivateKeyPasswordDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final parentContext = context;
    final passwordController = TextEditingController();
    var obscureText = true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.translate('enter_password')),
          content: TextField(
            controller: passwordController,
            obscureText: obscureText,
            decoration: InputDecoration(
              labelText: l10n.translate('password'),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    obscureText = !obscureText;
                  });
                },
              ),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _verifyAndShowPrivateKey(
              dialogContext,
              parentContext,
              ref,
              l10n,
              passwordController.text,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.translate('cancel')),
            ),
            ElevatedButton(
              onPressed: () => _verifyAndShowPrivateKey(
                dialogContext,
                parentContext,
                ref,
                l10n,
                passwordController.text,
              ),
              child: Text(l10n.translate('confirm')),
            ),
          ],
        ),
      ),
    );
  }

  void _verifyAndShowPrivateKey(
    BuildContext dialogContext,
    BuildContext parentContext,
    WidgetRef ref,
    AppLocalizations l10n,
    String password,
  ) {
    if (password.isEmpty) {
      toast.error(parentContext, l10n.translate('error_password_empty'));
      return;
    }

    final ok = ref.read(authProvider.notifier).verifyPassword(password);
    if (!ok) {
      toast.error(parentContext, l10n.translate('error_password_incorrect'));
      return;
    }

    Navigator.pop(dialogContext);
    Future.microtask(() {
      _showPrivateKeyDialog(parentContext, ref, l10n);
    });
  }

  /// 获取语言显示名称
  String _getLanguageName(String localeCode) {
    return AppLocalizations.languageNames[localeCode] ?? localeCode;
  }

  /// 显示语言选择对话框
  void _showLanguageDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final settings = ref.read(settingsProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppLocalizations.supportedLocales.map((locale) {
            final localeCode = locale.toString();
            final isSelected = settings.currentLocale.toString() == localeCode;

            return RadioListTile<String>(
              title: Text(
                AppLocalizations.languageNames[localeCode] ?? localeCode,
              ),
              value: localeCode,
              groupValue: settings.currentLocale.toString(),
              selected: isSelected,
              onChanged: (value) {
                if (value != null) {
                  ref
                      .read(settingsProvider.notifier)
                      .setLocale(_parseLocale(value));
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel')),
          ),
        ],
      ),
    );
  }

  /// 显示私钥对话框
  void _showPrivateKeyDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final authState = ref.read(authProvider);
    final privateKey = authState.privateKey;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.key, color: Colors.orange),
            const SizedBox(width: 8),
            Text(l10n.translate('private_key')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 警告信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.translate('private_key_security_warning'),
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 用户名
            Text(
              '${l10n.translate('username')}: ${authState.username}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),

            // 私钥显示
            Text(
              l10n.translate('private_key_value'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: SelectableText(
                privateKey,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          // 复制按钮
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(l10n.translate('copy_private_key')),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: privateKey));
              toast.success(context, l10n.translate('private_key_copied'));
            },
          ),

          // 关闭按钮
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('close')),
          ),
        ],
      ),
    );
  }

  /// 解析语言代码
  Locale _parseLocale(String localeCode) {
    final parts = localeCode.split('_');
    if (parts.length == 2) {
      return Locale(parts[0], parts[1]);
    }
    return Locale(localeCode);
  }
}
