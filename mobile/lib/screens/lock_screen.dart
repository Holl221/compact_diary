import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Экран блокировки. Два режима:
///  • setup   — пароль ещё не задан: придумываем и подтверждаем его;
///  • unlock  — пароль есть: вводим для входа.
class LockScreen extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onUnlocked;

  const LockScreen({
    super.key,
    required this.storage,
    required this.onUnlocked,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  final _focus = FocusNode();

  bool _isSetup = true;
  bool _checking = true;
  bool _obscure = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final has = await widget.storage.hasPassword();
    setState(() {
      _isSetup = !has;
      _checking = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pass = _controller.text;
    if (pass.trim().isEmpty) {
      setState(() => _error = 'Введите пароль');
      return;
    }

    if (_isSetup) {
      if (pass.length < 4) {
        setState(() => _error = 'Пароль должен быть не короче 4 символов');
        return;
      }
      if (pass != _confirmController.text) {
        setState(() => _error = 'Пароли не совпадают');
        return;
      }
      setState(() => _busy = true);
      await widget.storage.setPassword(pass);
      if (!mounted) return;
      widget.onUnlocked();
    } else {
      setState(() => _busy = true);
      final ok = await widget.storage.verifyPassword(pass);
      if (!mounted) return;
      if (ok) {
        widget.onUnlocked();
      } else {
        setState(() {
          _busy = false;
          _error = 'Неверный пароль';
          _controller.clear();
        });
        _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBadge(),
                    const SizedBox(height: 28),
                    Text(
                      _isSetup ? 'Добро пожаловать' : 'С возвращением',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSetup
                          ? 'Придумайте пароль для дневника.\nОн хранится только на этом устройстве.'
                          : 'Введите пароль, чтобы открыть дневник',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _passwordField(
                      controller: _controller,
                      hint: _isSetup ? 'Новый пароль' : 'Пароль',
                      onSubmitted: _isSetup ? null : (_) => _submit(),
                    ),
                    if (_isSetup) ...[
                      const SizedBox(height: 14),
                      _passwordField(
                        controller: _confirmController,
                        hint: 'Повторите пароль',
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF241B0E),
                              ),
                            )
                          : Text(_isSetup ? 'Создать дневник' : 'Войти'),
                    ),
                    const SizedBox(height: 16),
                    if (!_isSetup)
                      Text(
                        'Пароль забыли? К сожалению, восстановить его нельзя — '
                        'он не хранится в открытом виде.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textFaint,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge() {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(
          _isSetup ? Icons.auto_stories_outlined : Icons.lock_outline_rounded,
          color: AppColors.accent,
          size: 40,
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: controller == _controller ? _focus : null,
      obscureText: _obscure,
      autofocus: controller == _controller,
      textInputAction:
          onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      onSubmitted: onSubmitted,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      style: const TextStyle(fontSize: 17, letterSpacing: 1.5),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.key_rounded, color: AppColors.textFaint),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: AppColors.textFaint,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
