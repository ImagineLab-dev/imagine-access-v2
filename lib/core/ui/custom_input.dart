import 'package:flutter/material.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

class CustomInput extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final IconData? icon; // Alias for prefixIcon
  final String? prefixText; // New property
  final String? initialValue;
  final bool enabled;
  final TextInputType keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final Widget? prefixWidget; // New property

  const CustomInput({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.prefixIcon,
    this.icon,
    this.prefixText,
    this.initialValue,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.validator,
    this.onChanged,
    this.prefixWidget,
  });

  @override
  State<CustomInput> createState() => _CustomInputState();
}

class _CustomInputState extends State<CustomInput> {
  /// Solo aplica a campos de contraseña. Arranca oculto siempre: mostrarla por
  /// defecto expondría la clave a quien esté al lado, que en la puerta de un
  /// evento es bastante gente.
  bool _revelada = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final esPassword = widget.obscureText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            widget.label.toUpperCase(),
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color:
                    (isDark ? Colors.black : Colors.grey).withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: widget.controller,
            initialValue: widget.controller == null ? widget.initialValue : null,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            obscureText: esPassword && !_revelada,
            validator: widget.validator,
            onChanged: widget.onChanged,
            style: TextStyle(
              color: widget.enabled 
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white60 : Colors.black38),
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixText: widget.prefixText,
              prefixStyle: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54, 
                  fontWeight: FontWeight.bold,
                  fontSize: 16
              ),
              prefixIcon: widget.prefixWidget ?? ((widget.prefixIcon ?? widget.icon) != null 
                  ? Icon(
                      widget.prefixIcon ?? widget.icon, 
                      color: widget.enabled 
                        ? (isDark ? Colors.white54 : Colors.black45)
                        : (isDark ? Colors.white24 : Colors.black26)
                    )
                  : null),
              suffixIcon: esPassword
                  ? IconButton(
                      icon: Icon(
                        _revelada
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: isDark ? Colors.white54 : Colors.black45,
                        size: 20,
                      ),
                      tooltip: _revelada ? l10n.hidePassword : l10n.showPassword,
                      onPressed: () => setState(() => _revelada = !_revelada),
                    )
                  : null,
              fillColor: isDark 
                ? AppTheme.surfaceColor.withValues(alpha: widget.enabled ? 0.5 : 0.2)
                : AppTheme.lightInput,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.1)
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.1)
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.primaryColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
