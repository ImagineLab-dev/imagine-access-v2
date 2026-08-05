import 'package:flutter/material.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

import '../theme/app_theme.dart';

/// Campo de formulario del sistema.
///
/// La etiqueta va **dentro** de la caja, arriba y en chico; el valor va debajo
/// en monoespaciada. Es la forma de un campo de planilla técnica, y resuelve
/// algo práctico: la etiqueta acompaña al dato incluso cuando el campo está
/// lleno, sin gastar una línea extra de alto por encima como hacía antes.
///
/// El foco se marca engrosando el borde al color acento. Antes se marcaba con
/// una sombra difuminada debajo de cada campo —la misma sombra en todos, así
/// que no marcaba nada— y ese difuminado se dibujaba siempre, tuviera foco o
/// no.
class CustomInput extends StatefulWidget {
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
    this.maxLines = 1,
    this.codigo,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final IconData? prefixIcon;

  /// Alias histórico de [prefixIcon].
  final IconData? icon;

  final String? prefixText;
  final String? initialValue;
  final bool enabled;
  final TextInputType keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final Widget? prefixWidget;
  final int maxLines;

  /// Código corto que se muestra a la derecha de la etiqueta (`ID_01`,
  /// `PWD_02`). Es un guiño de formulario técnico; opcional.
  final String? codigo;

  @override
  State<CustomInput> createState() => _CustomInputState();
}

class _CustomInputState extends State<CustomInput> {
  /// Solo aplica a campos de contraseña. Arranca oculto siempre: mostrarla por
  /// defecto expondría la clave a quien esté al lado, que en la puerta de un
  /// evento es bastante gente.
  bool _revelada = false;

  late final FocusNode _foco;
  bool _enfocado = false;

  @override
  void initState() {
    super.initState();
    _foco = FocusNode()
      ..addListener(() {
        if (_enfocado != _foco.hasFocus) {
          setState(() => _enfocado = _foco.hasFocus);
        }
      });
  }

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final esPassword = widget.obscureText;
    final iconoPrefijo = widget.prefixIcon ?? widget.icon;

    final colorBorde = !widget.enabled
        ? AppTheme.bordeSuave(context)
        : _enfocado
            ? AppTheme.lima
            : AppTheme.borde(context);

    return FormField<String>(
      initialValue: widget.controller?.text ?? widget.initialValue,
      // El valor real vive en el controller, así que se lee de ahí y no del
      // estado del FormField: si el texto se cambia por código —autocompletar,
      // precargar un borrador— el estado queda viejo y validaría el valor
      // anterior. Este FormField solo existe para que el mensaje de error se
      // dibuje con la forma del sistema en lugar de la burbuja roja redondeada
      // de Material.
      validator: (valor) =>
          widget.validator?.call(widget.controller?.text ?? valor),
      builder: (estado) {
        final hayError = estado.hasError;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(
                color: widget.enabled
                    ? AppTheme.campo(context)
                    : AppTheme.campo(context).withValues(alpha: 0.45),
                border: Border.all(
                  color: hayError ? AppTheme.accentOrange : colorBorde,
                  width: _enfocado || hayError ? 1.6 : AppTheme.bordeAncho,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.label.toUpperCase(),
                          style: AppTheme.etiqueta(
                            context,
                            size: 10,
                            color: _enfocado
                                ? AppTheme.acentoTexto(context)
                                : AppTheme.textoSecundario(context),
                          ),
                        ),
                      ),
                      if (widget.codigo != null)
                        Text(
                          widget.codigo!,
                          style: AppTheme.dato(
                            context,
                            size: 9.5,
                            peso: FontWeight.w400,
                            color: AppTheme.textoApagado(context),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (widget.prefixWidget != null) ...[
                        widget.prefixWidget!,
                        const SizedBox(width: 8),
                      ] else if (iconoPrefijo != null) ...[
                        Icon(iconoPrefijo,
                            size: 16, color: AppTheme.textoApagado(context)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: TextFormField(
                          focusNode: _foco,
                          controller: widget.controller,
                          initialValue: widget.controller == null
                              ? widget.initialValue
                              : null,
                          enabled: widget.enabled,
                          keyboardType: widget.keyboardType,
                          obscureText: esPassword && !_revelada,
                          maxLines: esPassword ? 1 : widget.maxLines,
                          onChanged: (valor) {
                            estado.didChange(valor);
                            widget.onChanged?.call(valor);
                          },
                          style: AppTheme.dato(
                            context,
                            size: 14,
                            peso: FontWeight.w500,
                            color: widget.enabled
                                ? AppTheme.texto(context)
                                : AppTheme.textoApagado(context),
                          ),
                          cursorColor: AppTheme.lima,
                          cursorWidth: 2,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            // El error lo dibuja el FormField de afuera; si lo
                            // dibujara también acá saldría dos veces.
                            errorStyle: const TextStyle(height: 0, fontSize: 0),
                            hintText: widget.hint,
                            hintStyle: AppTheme.dato(
                              context,
                              size: 13.5,
                              peso: FontWeight.w400,
                              color: AppTheme.textoApagado(context),
                            ),
                            prefixText: widget.prefixText,
                            prefixStyle: AppTheme.dato(
                              context,
                              size: 14,
                              color: AppTheme.textoSecundario(context),
                            ),
                          ),
                        ),
                      ),
                      if (esPassword)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(
                            _revelada
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                            color: AppTheme.textoSecundario(context),
                          ),
                          tooltip:
                              _revelada ? l10n.hidePassword : l10n.showPassword,
                          onPressed: () => setState(() => _revelada = !_revelada),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (hayError)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline,
                        size: 13, color: AppTheme.peligroTexto(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        estado.errorText!,
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11.5,
                          height: 1.35,
                          color: AppTheme.peligroTexto(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
