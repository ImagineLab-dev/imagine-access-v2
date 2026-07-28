import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'auth_controller.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/ui/neon_button.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_handler.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String email;
  final String displayName;
  final String organizationName;
  final String? country;

  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.displayName,
    required this.organizationName,
    this.country,
  });

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _canResend = false;
  int _resendCountdown = 60;
  Timer? _timer;
  int _verifyAttempts = 0;
  DateTime? _verifyLockoutEnd;
  static const int _maxVerifyAttempts = 5;
  static const int _verifyLockoutSeconds = 60;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _canResend = false;
      _resendCountdown = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);

    // Rate limiting: check lockout
    if (_verifyLockoutEnd != null && DateTime.now().isBefore(_verifyLockoutEnd!)) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          l10n.tooManyAttempts,
        );
      }
      return;
    }

    _verifyAttempts++;
    if (_verifyAttempts >= _maxVerifyAttempts) {
      _verifyLockoutEnd = DateTime.now().add(Duration(seconds: _verifyLockoutSeconds));
      _verifyAttempts = 0;
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          l10n.tooManyAttempts,
        );
      }
      return;
    }

    try {
      await ref.read(authControllerProvider.notifier).verifyOtpAndSetupProfile(
            widget.email,
            _otpController.text.trim(),
            widget.displayName,
            widget.organizationName,
            country: widget.country,
          );
      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, l10n.verifyEmailError);
      }
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(authControllerProvider.notifier).resendOtp(widget.email);
      if (!mounted) return;
      _startResendTimer();
      if (mounted) {
        ErrorHandler.showSuccessSnackBar(
          context,
          l10n.verifyEmailResent,
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, l10n.resendCodeError);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;

    return GlassScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                const Icon(Icons.mark_email_read_outlined,
                        size: 72, color: Colors.white)
                    .animate()
                    .scale(duration: 400.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 24),
                Text(
                  l10n.verifyEmailTitle,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    letterSpacing: 0.5,
                  ),
                ).animate().fade().slideY(begin: 0.2, end: 0),
                const SizedBox(height: 12),
                Text(
                  l10n.verifyEmailSubtitle(widget.email),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ).animate().fade(delay: 100.ms),
                const SizedBox(height: 32),
                GlassCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 6,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: theme.textTheme.headlineMedium?.copyWith(
                            letterSpacing: 12,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '000000',
                            hintStyle: TextStyle(
                              letterSpacing: 12,
                              color: textColor.withValues(alpha: 0.3),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: textColor.withValues(alpha: 0.2),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppTheme.primaryColor,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return l10n.required;
                            }
                            if (v.length != 6) {
                              return l10n.verifyEmailInvalidCode;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        NeonButton(
                          text: l10n.verifyEmailButton.toUpperCase(),
                          isLoading: isLoading,
                          onPressed: _verifyOtp,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _canResend ? _resendCode : null,
                          child: Text(
                            _canResend
                                ? l10n.verifyEmailResendButton
                                : l10n.verifyEmailResendWait(
                                    _resendCountdown),
                            style: TextStyle(
                              color: _canResend
                                  ? AppTheme.primaryColor
                                  : textColor.withValues(alpha: 0.5),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fade(delay: 200.ms).slideY(begin: 0.1, end: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
