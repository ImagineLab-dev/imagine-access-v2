import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:imagine_access/core/constants/app_roles.dart';
import 'package:imagine_access/core/i18n/locale_provider.dart';
import 'package:imagine_access/core/platform/file_picker.dart';
import 'package:imagine_access/core/theme/app_theme.dart';
import 'package:imagine_access/core/theme/theme_provider.dart';
import 'package:imagine_access/core/ui/glass_card.dart';
import 'package:imagine_access/core/ui/glass_scaffold.dart';
import 'package:imagine_access/features/auth/presentation/auth_controller.dart';
import 'package:imagine_access/features/profile/data/profile_repository.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  final _orgNombreCtrl = TextEditingController();
  final _orgRazonCtrl = TextEditingController();
  final _orgRucCtrl = TextEditingController();
  final _orgEmailCtrl = TextEditingController();
  final _orgTelCtrl = TextEditingController();
  final _orgDireccionCtrl = TextEditingController();

  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();

  // Los campos se rellenan una sola vez desde el provider. Sin esta bandera,
  // cada rebuild pisaría lo que el usuario está tipeando.
  bool _perfilCargado = false;
  bool _orgCargada = false;

  bool _guardandoPerfil = false;
  bool _guardandoOrg = false;
  bool _cambiandoPass = false;
  bool _subiendoFoto = false;

  String? _avatarUrl;

  @override
  void dispose() {
    for (final c in [
      _nombreCtrl, _telefonoCtrl,
      _orgNombreCtrl, _orgRazonCtrl, _orgRucCtrl,
      _orgEmailCtrl, _orgTelCtrl, _orgDireccionCtrl,
      _passCtrl, _passConfirmCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _aviso(String mensaje, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Se limpia antes de mostrar: sin esto los avisos se apilan y el usuario
    // ve el de hace tres acciones.
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  // ---------------------------------------------------------------- acciones

  Future<void> _elegirFoto(AppLocalizations l10n) async {
    final repo = ref.read(profileRepositoryProvider);
    final archivo = await pickFile(accept: 'image/*');
    if (archivo == null) return;

    if (archivo.bytes.lengthInBytes > ProfileRepository.maxAvatarBytes) {
      _aviso(l10n.photoTooLarge, error: true);
      return;
    }

    setState(() => _subiendoFoto = true);
    try {
      final url = await repo.uploadAvatar(
        archivo.bytes,
        archivo.extension.isEmpty ? 'jpg' : archivo.extension,
      );
      await repo.updateProfile(
        displayName: _nombreCtrl.text,
        phone: _telefonoCtrl.text,
        avatarUrl: url,
      );
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      ref.invalidate(profileProvider);
      _aviso(l10n.profileSaved);
    } catch (_) {
      _aviso(l10n.photoUploadError, error: true);
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _quitarFoto(AppLocalizations l10n) async {
    final repo = ref.read(profileRepositoryProvider);
    setState(() => _subiendoFoto = true);
    try {
      await repo.updateProfile(
        displayName: _nombreCtrl.text,
        phone: _telefonoCtrl.text,
        avatarUrl: '',
      );
      if (!mounted) return;
      setState(() => _avatarUrl = null);
      ref.invalidate(profileProvider);
      _aviso(l10n.profileSaved);
    } catch (_) {
      _aviso(l10n.profileSaveError, error: true);
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _guardarPerfil(AppLocalizations l10n) async {
    if (_nombreCtrl.text.trim().isEmpty) {
      _aviso(l10n.required, error: true);
      return;
    }
    setState(() => _guardandoPerfil = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            displayName: _nombreCtrl.text,
            phone: _telefonoCtrl.text,
          );
      ref.invalidate(profileProvider);
      _aviso(l10n.profileSaved);
    } catch (_) {
      _aviso(l10n.profileSaveError, error: true);
    } finally {
      if (mounted) setState(() => _guardandoPerfil = false);
    }
  }

  Future<void> _guardarOrganizacion(AppLocalizations l10n) async {
    if (_orgNombreCtrl.text.trim().isEmpty) {
      _aviso(l10n.required, error: true);
      return;
    }
    setState(() => _guardandoOrg = true);
    try {
      await ref.read(profileRepositoryProvider).updateOrganization(
            name: _orgNombreCtrl.text,
            legalName: _orgRazonCtrl.text,
            taxId: _orgRucCtrl.text,
            contactEmail: _orgEmailCtrl.text,
            contactPhone: _orgTelCtrl.text,
            address: _orgDireccionCtrl.text,
          );
      ref.invalidate(organizationDetailsProvider);
      _aviso(l10n.orgSaved);
    } catch (_) {
      _aviso(l10n.orgSaveError, error: true);
    } finally {
      if (mounted) setState(() => _guardandoOrg = false);
    }
  }

  Future<void> _cambiarPassword(AppLocalizations l10n) async {
    final nueva = _passCtrl.text;
    if (nueva.length < 8) {
      _aviso(l10n.passwordMinLength, error: true);
      return;
    }
    if (nueva != _passConfirmCtrl.text) {
      _aviso(l10n.passwordsDoNotMatch, error: true);
      return;
    }
    setState(() => _cambiandoPass = true);
    try {
      await ref.read(profileRepositoryProvider).changePassword(nueva);
      _passCtrl.clear();
      _passConfirmCtrl.clear();
      _aviso(l10n.passwordChanged);
    } catch (_) {
      _aviso(l10n.passwordChangeError, error: true);
    } finally {
      if (mounted) setState(() => _cambiandoPass = false);
    }
  }

  Future<void> _cerrarOtrasSesiones(AppLocalizations l10n) async {
    try {
      await ref.read(profileRepositoryProvider).signOutOtherSessions();
      _aviso(l10n.otherSessionsClosed);
    } catch (_) {
      _aviso(l10n.profileSaveError, error: true);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final perfilAsync = ref.watch(profileProvider);
    final esAdmin = AppRoles.isAdmin(ref.watch(userRoleProvider));

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.profile)),
      body: perfilAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.profileSaveError)),
        data: (perfil) {
          if (perfil != null && !_perfilCargado) {
            _perfilCargado = true;
            _nombreCtrl.text = perfil.displayName;
            _telefonoCtrl.text = perfil.phone ?? '';
            _avatarUrl = perfil.avatarUrl;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _seccionDatos(l10n, perfil),
              const SizedBox(height: 16),
              _seccionSeguridad(l10n),
              const SizedBox(height: 16),
              _seccionPreferencias(l10n),
              const SizedBox(height: 16),
              _seccionOrganizacion(l10n, esAdmin),
            ],
          );
        },
      ),
    );
  }

  Widget _titulo(String texto, IconData icono) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icono, size: 20, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Text(texto,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController ctrl, String etiqueta,
      {bool habilitado = true,
      TextInputType? tipo,
      bool oculto = false,
      String? ayuda}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        enabled: habilitado,
        obscureText: oculto,
        keyboardType: tipo,
        decoration: InputDecoration(
          labelText: etiqueta,
          helperText: ayuda,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _seccionDatos(AppLocalizations l10n, UserProfile? perfil) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo(l10n.accountData, Icons.person_outline),
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: .15),
                backgroundImage:
                    _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                child: _avatarUrl == null
                    ? const Icon(Icons.person, size: 34)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed:
                          _subiendoFoto ? null : () => _elegirFoto(l10n),
                      icon: _subiendoFoto
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_outlined, size: 18),
                      label: Text(l10n.changePhoto),
                    ),
                    if (_avatarUrl != null)
                      TextButton(
                        onPressed:
                            _subiendoFoto ? null : () => _quitarFoto(l10n),
                        child: Text(l10n.removePhoto),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _campo(_nombreCtrl, l10n.displayName),
          _campo(
            TextEditingController(text: perfil?.email ?? ''),
            l10n.email,
            habilitado: false,
            ayuda: l10n.emailCannotChange,
          ),
          _campo(_telefonoCtrl, l10n.phoneOptional, tipo: TextInputType.phone),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: _guardandoPerfil ? null : () => _guardarPerfil(l10n),
            child: _guardandoPerfil
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Widget _seccionSeguridad(AppLocalizations l10n) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo(l10n.security, Icons.lock_outline),
          _campo(_passCtrl, l10n.newPassword, oculto: true),
          _campo(_passConfirmCtrl, l10n.confirmPassword, oculto: true),
          FilledButton(
            onPressed: _cambiandoPass ? null : () => _cambiarPassword(l10n),
            child: _cambiandoPass
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.changePassword),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.signOutOtherSessions),
            subtitle: Text(l10n.signOutOtherSessionsHint),
            trailing: const Icon(Icons.logout, size: 20),
            onTap: () => _cerrarOtrasSesiones(l10n),
          ),
        ],
      ),
    );
  }

  Widget _seccionPreferencias(AppLocalizations l10n) {
    final modo = ref.watch(themeNotifierProvider);
    final locale = ref.watch(localeProvider);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo(l10n.preferences, Icons.tune),
          DropdownButtonFormField<ThemeMode>(
            initialValue: modo,
            decoration: InputDecoration(
              labelText: l10n.theme,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                  value: ThemeMode.system, child: Text(l10n.themeSystem)),
              DropdownMenuItem(
                  value: ThemeMode.light, child: Text(l10n.themeLight)),
              DropdownMenuItem(
                  value: ThemeMode.dark, child: Text(l10n.themeDark)),
            ],
            onChanged: (valor) {
              if (valor != null) {
                ref.read(themeNotifierProvider.notifier).setTheme(valor);
              }
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: locale.languageCode,
            decoration: InputDecoration(
              labelText: l10n.language,
              border: const OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'es', child: Text('Español')),
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'pt', child: Text('Português')),
            ],
            onChanged: (valor) {
              if (valor != null) {
                ref.read(localeProvider.notifier).changeLocale(Locale(valor));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _seccionOrganizacion(AppLocalizations l10n, bool esAdmin) {
    final orgAsync = ref.watch(organizationDetailsProvider);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: orgAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => Text(l10n.orgSaveError),
        data: (org) {
          if (org == null) return const SizedBox.shrink();

          if (!_orgCargada) {
            _orgCargada = true;
            _orgNombreCtrl.text = org.name;
            _orgRazonCtrl.text = org.legalName ?? '';
            _orgRucCtrl.text = org.taxId ?? '';
            _orgEmailCtrl.text = org.contactEmail ?? '';
            _orgTelCtrl.text = org.contactPhone ?? '';
            _orgDireccionCtrl.text = org.address ?? '';
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titulo(l10n.organization, Icons.apartment_outlined),
              if (!esAdmin)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    l10n.orgAdminOnly,
                    style: TextStyle(
                        color: Theme.of(context).hintColor, fontSize: 13),
                  ),
                ),
              _campo(_orgNombreCtrl, l10n.orgCommercialName,
                  habilitado: esAdmin),
              _campo(_orgRazonCtrl, l10n.orgLegalName,
                  habilitado: esAdmin, ayuda: l10n.orgBillingHint),
              _campo(_orgRucCtrl, l10n.orgTaxId, habilitado: esAdmin),
              _campo(_orgEmailCtrl, l10n.orgContactEmail,
                  habilitado: esAdmin, tipo: TextInputType.emailAddress),
              _campo(_orgTelCtrl, l10n.orgContactPhone,
                  habilitado: esAdmin, tipo: TextInputType.phone),
              _campo(_orgDireccionCtrl, l10n.orgAddress, habilitado: esAdmin),
              if (esAdmin)
                FilledButton(
                  onPressed: _guardandoOrg
                      ? null
                      : () => _guardarOrganizacion(l10n),
                  child: _guardandoOrg
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.save),
                ),
            ],
          );
        },
      ),
    );
  }
}
