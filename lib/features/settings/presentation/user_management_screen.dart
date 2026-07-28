import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

import '../../../core/constants/app_roles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/settings_repository.dart';

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersListProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.teamMembers),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showAddUserDialog(context, ref),
            tooltip: l10n.addMember,
          ),
        ],
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) =>
            Center(child: Text(l10n.error, style: theme.textTheme.bodyMedium)),
        data: (users) {
          if (users.isEmpty) {
            return Center(child: Text(l10n.noUsersFound, style: theme.textTheme.bodyMedium));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final user = users[index];
              final role = (user['role'] as String?) ?? 'rrpp';
              final currentUserId = ref.read(userProvider)?.id;
              final isSelf = user['user_id'] == currentUserId;

              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;

              return GlassCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getRoleColor(role).withValues(alpha: 0.2),
                      child: Icon(Icons.person, color: _getRoleColor(role)),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        user['display_name'] ?? l10n.unknown,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (isSelf)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          AppRoles.label(role),
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else if (!AppRoles.all.contains(role))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          AppRoles.label(role),
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      DropdownButton<String>(
                        value: role,
                        dropdownColor: isDark ? Colors.black87 : Colors.white,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(
                            value: AppRoles.admin,
                            child: Text(
                              AppRoles.label(AppRoles.admin),
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          DropdownMenuItem(
                            value: AppRoles.rrpp,
                            child: Text(
                              AppRoles.label(AppRoles.rrpp),
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          DropdownMenuItem(
                            value: AppRoles.door,
                            child: Text(
                              AppRoles.label(AppRoles.door),
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                        ],
                        onChanged: (newRole) async {
                          if (newRole != null && newRole != role) {
                            final currentUserId = ref.read(userProvider)?.id;
                            if (user['user_id'] == currentUserId) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.cannotChangeOwnRole)),
                              );
                              return;
                            }
                            try {
                              await ref.read(settingsRepositoryProvider).updateUserRole(
                                    user['user_id'],
                                    newRole,
                                  );
                              ref.invalidate(usersListProvider);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.eventSaveError)),
                                );
                              }
                            }
                          }
                        },
                      ),
                    if (!isSelf) ...[
                      const SizedBox(width: 8),
                      IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _confirmDelete(context, ref, user),
                        ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case AppRoles.admin:
        return Colors.redAccent;
      case AppRoles.rrpp:
        return AppTheme.neonBlue;
      case AppRoles.door:
        return AppTheme.accentGreen;
      default:
        return Colors.grey;
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Map<String, dynamic> user) {
    final l10n = AppLocalizations.of(context);
    final currentUserId = ref.read(userProvider)?.id;

    if (user['user_id'] == currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cannotDeleteSelf)),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteMemberQuestion),
        content: Text(l10n.confirmRemoveMember(user['display_name'] ?? l10n.unknown)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(settingsRepositoryProvider).deleteUserProfile(user['user_id']);
                ref.invalidate(usersListProvider);
                if (context.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.deleteErrorMessage)),
                  );
                }
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddUserDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String selectedRole = AppRoles.rrpp;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: isDark ? AppTheme.surfaceColor : Colors.white,
          title: Text(
            l10n.addTeamMember,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(labelText: l10n.email),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: l10n.displayName),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  dropdownColor: isDark ? Colors.black87 : Colors.white,
                  items: [
                    DropdownMenuItem(
                      value: AppRoles.admin,
                      child: Text(
                        AppRoles.label(AppRoles.admin),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    DropdownMenuItem(
                      value: AppRoles.rrpp,
                      child: Text(
                        AppRoles.label(AppRoles.rrpp),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    DropdownMenuItem(
                      value: AppRoles.door,
                      child: Text(
                        AppRoles.label(AppRoles.door),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => selectedRole = v!),
                  decoration: InputDecoration(labelText: l10n.roleLabel),
                ),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty) {
                        return;
                      }
                      final emailRegex = RegExp(
                          r'^[a-zA-Z0-9.!#$%&\x27*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$');
                      if (!emailRegex.hasMatch(email)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.invalidEmail)),
                        );
                        return;
                      }

                      setState(() => isLoading = true);
                      try {
                        final result = await ref.read(settingsRepositoryProvider).createUser(
                              email: emailCtrl.text.trim(),
                              displayName: nameCtrl.text.trim(),
                              role: selectedRole,
                            );

                        ref.invalidate(usersListProvider);
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          final tempPassword = result['temp_password'] as String?;
                          if (tempPassword != null) {
                            _showTempPasswordDialog(context, emailCtrl.text.trim(), tempPassword);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.userCreatedSuccessfully)),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.error),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } finally {
                        // El botón se libera pase lo que pase. Antes solo se
                        // liberaba dentro del catch Y con el contexto montado:
                        // cualquier otro camino dejaba el diálogo con la rueda
                        // girando y el botón muerto.
                        if (ctx.mounted) setState(() => isLoading = false);
                      }
                    },
              child: Text(l10n.createUser),
            ),
          ],
        ),
      ),
    );
  }

  void _showTempPasswordDialog(BuildContext context, String email, String password) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.userCreatedTitle, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.emailWithValue(email), style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            Text(
              l10n.temporaryPassword,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      password,
                      style: const TextStyle(
                        color: AppTheme.neonBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18, color: AppTheme.neonBlue),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: password));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.passwordCopied)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ ${l10n.savePasswordWarning}',
              style: const TextStyle(color: Colors.amber, fontSize: 12),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.understood),
          ),
        ],
      ),
    );
  }
}
