import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/ui/custom_input.dart';
import '../../../core/ui/neon_button.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_handler.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKeyEmail = GlobalKey<FormState>();
  final _formKeyOtp = GlobalKey<FormState>();
  final _formKeyPassword = GlobalKey<FormState>();

  // 0 = email, 1 = OTP code, 2 = new password
  int _step = 0;
  bool _isLoading = false;
  bool _canResend = false;
  int _resendCountdown = 60;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _canResend = false;
      _resendCountdown = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          _canResend = true;
          t.cancel();
        }
      });
    });
  }

  Future<void> _sendResetCode() async {
    if (!_formKeyEmail.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _step = 1);
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).resetCodeSent)),
      );
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, ErrorHandler.getErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Step 2: Only validates OTP format and advances to password step.
  /// No API call here — OTP is verified together with password change.
  void _confirmCode() {
    if (!_formKeyOtp.currentState!.validate()) return;
    setState(() => _step = 2);
  }

  /// Step 3: Atomic operation — verifyOTP + updateUser + signOut.
  /// No intermediate session state that could corrupt the app.
  Future<void> _changePassword() async {
    if (!_formKeyPassword.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final l10n = AppLocalizations.of(context);
    try {
      // 1. Verify OTP → creates a recovery session
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: _emailController.text.trim(),
        token: _otpController.text.trim(),
        type: OtpType.recovery,
      );
      if (!mounted) return;
      if (response.session == null) {
        ErrorHandler.showErrorSnackBar(context, l10n.resetCodeInvalid);
        setState(() => _step = 1);
        return;
      }

      // 2. Immediately update password using the recovery session
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text),
      );

      // 3. Clean sign out
      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.passwordChanged)),
      );
      context.go('/login');
    } on AuthException catch (e) {
      if (mounted) {
        final msg = e.message.contains('otp_expired') ||
                e.message.contains('invalid') ||
                e.statusCode == '401'
            ? l10n.resetCodeInvalid
            : ErrorHandler.getErrorMessage(e);
        ErrorHandler.showErrorSnackBar(context, msg);
        // If OTP was invalid, go back to code step
        if (msg == l10n.resetCodeInvalid) {
          setState(() => _step = 1);
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, ErrorHandler.getErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.resetPassword),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            child: switch (_step) {
              0 => _buildEmailForm(l10n, isDark, textColor),
              1 => _buildOtpForm(l10n, isDark, textColor),
              _ => _buildPasswordForm(l10n, isDark, textColor),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmailForm(AppLocalizations l10n, bool isDark, Color textColor) {
    return Form(
      key: _formKeyEmail,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_reset, size: 48, color: AppTheme.neonBlue),
          const SizedBox(height: 16),
          Text(
            l10n.enterEmailToReset,
            textAlign: TextAlign.center,
            style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 14),
          ),
          const SizedBox(height: 24),
          CustomInput(
            label: l10n.email,
            controller: _emailController,
            prefixIcon: Icons.email_outlined,
            validator: (v) {
              if (v == null || v.isEmpty) return l10n.required;
              final emailRegex = RegExp(r'^[\w\-\.\+]+@([\w\-]+\.)+[\w\-]{2,}$');
              if (!emailRegex.hasMatch(v)) return l10n.invalidEmail;
              return null;
            },
          ),
          const SizedBox(height: 24),
          NeonButton(
            text: l10n.sendResetCode,
            isLoading: _isLoading,
            onPressed: _sendResetCode,
          ),
        ],
      ),
    );
  }

  Widget _buildOtpForm(AppLocalizations l10n, bool isDark, Color textColor) {
    return Form(
      key: _formKeyOtp,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mark_email_read, size: 48, color: AppTheme.accentGreen),
          const SizedBox(height: 16),
          Text(
            l10n.enterResetCode,
            textAlign: TextAlign.center,
            style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 14),
          ),
          const SizedBox(height: 24),
          CustomInput(
            label: l10n.enterResetCode,
            controller: _otpController,
            prefixIcon: Icons.pin,
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v == null || v.isEmpty) return l10n.required;
              if (v.length != 6) return l10n.resetCodeInvalid;
              return null;
            },
          ),
          const SizedBox(height: 24),
          NeonButton(
            text: l10n.confirm.toUpperCase(),
            isLoading: _isLoading,
            onPressed: _confirmCode,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _canResend ? _sendResetCode : null,
            child: Text(
              _canResend
                  ? l10n.sendResetCode
                  : '${l10n.sendResetCode} ($_resendCountdown)',
              style: TextStyle(
                color: _canResend ? AppTheme.neonBlue : textColor.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordForm(AppLocalizations l10n, bool isDark, Color textColor) {
    return Form(
      key: _formKeyPassword,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_open, size: 48, color: AppTheme.neonBlue),
          const SizedBox(height: 16),
          Text(
            l10n.newPassword,
            textAlign: TextAlign.center,
            style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 14),
          ),
          const SizedBox(height: 24),
          CustomInput(
            label: l10n.newPassword,
            controller: _newPasswordController,
            prefixIcon: Icons.lock_outline,
            obscureText: true,
            validator: (v) {
              if (v == null || v.isEmpty) return l10n.required;
              if (v.length < 8) return l10n.passwordMinLength;
              return null;
            },
          ),
          const SizedBox(height: 12),
          CustomInput(
            label: l10n.confirmNewPassword,
            controller: _confirmPasswordController,
            prefixIcon: Icons.lock_outline,
            obscureText: true,
            validator: (v) {
              if (v == null || v.isEmpty) return l10n.required;
              if (v != _newPasswordController.text) return l10n.passwordsDoNotMatch;
              return null;
            },
          ),
          const SizedBox(height: 24),
          NeonButton(
            text: l10n.changePassword,
            isLoading: _isLoading,
            onPressed: _changePassword,
          ),
        ],
      ),
    );
  }
}
