import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:repertorio_bc/core/providers/theme_provider.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/features/settings/notification_card.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:repertorio_bc/core/notifications/push_service.dart';
import 'package:repertorio_bc/core/offline/sync_manager.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  bool _hasPushPermission = false;
  bool _pushSupported = true;
  String? _pushUnavailableMessage;
  List<Map<String, dynamic>> _lastNotifications = [];
  bool _loadingNotifications = true;
  bool _isInit = false;
  bool _isDeletingAccount = false;
  bool _isRepairingFiles = false;

  @override
  void initState() {
    super.initState();
    _checkPushPermission();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      _loadNotifications();
      _isInit = true;
    }
  }

  Future<void> _loadNotifications() async {
    final perfil = ref.read(perfilProvider).value;
    if (perfil == null) return;

    final cacheKey = AppCache.userKey(
      'avisos_json',
      SupabaseService.client.auth.currentUser?.id,
      scope: perfil.coroId,
    );
    var cached = AppCache.get<String>(cacheKey);
    cached ??= AppCache.get<String>('avisos_json');
    if (cached != null && AppCache.get<String>(cacheKey) == null) {
      await AppCache.put(cacheKey, cached);
      await AppCache.delete('avisos_json');
    }
    if (cached != null) {
      try {
        final List<dynamic> decoded = jsonDecode(cached);
        setState(() {
          _lastNotifications = List<Map<String, dynamic>>.from(decoded);
          _loadingNotifications = false;
        });
      } catch (_) {}
    }

    try {
      final res = await SupabaseService.client
          .from('avisos')
          .select()
          .or('coro_id.eq.${perfil.coroId},coro_id.eq.estatal')
          .order('creado_en', ascending: false)
          .limit(6);

      await AppCache.put(cacheKey, jsonEncode(res));

      if (mounted) {
        setState(() {
          _lastNotifications = List<Map<String, dynamic>>.from(res);
          _loadingNotifications = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando historial de avisos: $e');
      if (mounted && _lastNotifications.isEmpty) {
        setState(() {
          _loadingNotifications = false;
        });
      }
    }
  }

  String _formatFecha(String creadoEnStr) {
    try {
      final date = DateTime.parse(creadoEnStr).toLocal();
      final now = DateTime.now();
      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      return '${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _checkPushPermission() async {
    if (!PushService.isAvailable) {
      if (!mounted) return;
      setState(() {
        _hasPushPermission = false;
        _pushSupported = false;
        _pushUnavailableMessage = PushService.unavailableReason ??
            'Este dispositivo no permite activar notificaciones.';
      });
      return;
    }
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (!mounted) return;
      setState(() {
        _pushSupported = true;
        _hasPushPermission =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pushSupported = false;
        _pushUnavailableMessage =
            'El servicio de notificaciones no está disponible en este dispositivo.';
      });
    }
  }

  Future<void> _requestPushPermission() async {
    if (!PushService.isAvailable) {
      await _checkPushPermission();
      return;
    }
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final isAuthorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    setState(() {
      _hasPushPermission = isAuthorized;
    });

    if (isAuthorized) {
      final registered = await registrarFcmTokenUsuarioActual();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(registered
                ? '¡Notificaciones push activadas con exito!'
                : 'El permiso esta activo. El dispositivo se registrara automaticamente cuando tenga conexion.'),
            backgroundColor: registered ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Permiso bloqueado'),
            content: const Text(
              'Las notificaciones están desactivadas en los Ajustes de tu iPhone. Para recibirlas, ve a Ajustes del sistema > Repertorio BC > Notificaciones y activa "Permitir notificaciones".',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _confirmAndDeleteAccount() async {
    final understood = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        title: const Text('Eliminar cuenta permanentemente'),
        content: const Text(
          'Se eliminarán tu cuenta, perfil, suscripciones de notificaciones '
          'y demás datos personales asociados. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (understood != true || !mounted) return;

    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Escribe ELIMINAR para confirmar.'),
            const SizedBox(height: 12),
            TextField(
              controller: confirmationController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'ELIMINAR',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: confirmationController,
            builder: (context, value, child) {
              final canDelete = value.text.trim().toUpperCase() == 'ELIMINAR';
              return FilledButton(
                onPressed:
                    canDelete ? () => Navigator.pop(dialogContext, true) : null,
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Eliminar definitivamente'),
              );
            },
          ),
        ],
      ),
    );
    confirmationController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await AuthController.deleteAccount();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tu cuenta y tus datos fueron eliminados.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar la cuenta. Comprueba tu conexión e inténtalo '
            'de nuevo.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('Error eliminando cuenta: $error');
    }
  }

  Future<void> _launchURL(String urlString) async {
    final Uri uri = Uri.parse(urlString);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error abriendo URL: $e');
    }
  }

  Future<void> _openAccountAndPrivacy() async {
    final wantsToDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.manage_accounts_outlined),
        title: const Text('Cuenta, soporte y privacidad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.help_outline_rounded),
              title: const Text('Soporte y Ayuda'),
              subtitle: const Text('Centro de soporte y contacto técnico'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () {
                _launchURL('https://www.lldmcorobc.com/soporte');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Política de privacidad'),
              subtitle: const Text('Protección de datos personales'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () {
                _launchURL('https://www.lldmcorobc.com/privacy.html');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Términos de uso (EULA)'),
              subtitle: const Text('Términos estándar de Apple'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () {
                _launchURL(
                    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
              ),
              title: const Text(
                'Eliminar cuenta',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: const Text(
                'Elimina permanentemente tu perfil y datos personales.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    if (wantsToDelete == true && mounted) {
      await _confirmAndDeleteAccount();
    }
  }

  Future<void> _repairFiles() async {
    if (_isRepairingFiles) return;
    setState(() => _isRepairingFiles = true);
    try {
      ref.invalidate(cantosBaseProvider);
      final cantos = await ref.read(cantosBaseProvider.future);
      ref.read(syncManagerProvider.notifier).repairNow(cantos);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Revisión iniciada. Se actualizarán los archivos faltantes o dañados.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo iniciar la reparación: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRepairingFiles = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTheme = ref.watch(themeProvider);
    final useOledDarkMode = ref.watch(oledDarkModeProvider);
    final selectedAccentColor = ref.watch(accentColorProvider);
    final accentColor = Theme.of(context).colorScheme.primary;
    final isCarousel = ref.watch(pdfNavModeProvider);
    final syncState = ref.watch(syncManagerProvider);

    // Auth Data
    final user = ref.watch(authUserProvider).value;
    final perfil = ref.watch(perfilProvider).value;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ajustes',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: Theme.of(context).colorScheme.onSurface),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 1. PERFIL
              _buildSectionTitle('PERFIL DE USUARIO'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      perfil?.nombre ?? 'Cargando...',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.isAnonymous == true
                          ? 'Cuenta de Invitado'
                          : (user?.email ?? 'Cargando...'),
                      style: GoogleFonts.inter(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (user?.isAnonymous == true)
                          TextButton.icon(
                            onPressed: () async {
                              final emailCtrl = TextEditingController();
                              final passCtrl = TextEditingController();
                              await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Vincular Correo'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(
                                        controller: emailCtrl,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        decoration: const InputDecoration(
                                            labelText: 'Correo Electrónico'),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: passCtrl,
                                        obscureText: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Contraseña'),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('Cancelar')),
                                    TextButton(
                                      onPressed: () async {
                                        if (emailCtrl.text.isNotEmpty &&
                                            passCtrl.text.isNotEmpty) {
                                          try {
                                            await SupabaseService.client.auth
                                                .updateUser(UserAttributes(
                                                    email: emailCtrl.text,
                                                    password: passCtrl.text));
                                            if (c.mounted) {
                                              Navigator.pop(c, true);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          'Cuenta vinculada correctamente',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .white)),
                                                      backgroundColor:
                                                          Colors.green));
                                            }
                                          } catch (e) {
                                            if (c.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                      content:
                                                          Text('Error: $e')));
                                            }
                                          }
                                        }
                                      },
                                      child: const Text('Vincular'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            icon: const Icon(Icons.link_rounded,
                                size: 18, color: Colors.green),
                            label: Text('Vincular',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        if (user?.isAnonymous != true)
                          TextButton.icon(
                            onPressed: () async {
                              final passCtrl = TextEditingController();
                              final confirmCtrl = TextEditingController();
                              await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Cambiar Contraseña'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(
                                        controller: passCtrl,
                                        obscureText: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Nueva Contraseña'),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: confirmCtrl,
                                        obscureText: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Confirmar Contraseña'),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('Cancelar')),
                                    TextButton(
                                      onPressed: () async {
                                        if (passCtrl.text.isNotEmpty &&
                                            passCtrl.text == confirmCtrl.text) {
                                          try {
                                            await SupabaseService.client.auth
                                                .updateUser(UserAttributes(
                                                    password: passCtrl.text));
                                            if (c.mounted) {
                                              Navigator.pop(c, true);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          'Contraseña actualizada',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .white)),
                                                      backgroundColor:
                                                          Colors.green));
                                            }
                                          } catch (e) {
                                            if (c.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                      content:
                                                          Text('Error: $e')));
                                            }
                                          }
                                        } else {
                                          ScaffoldMessenger.of(c).showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Las contraseñas no coinciden')));
                                        }
                                      },
                                      child: const Text('Guardar'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            icon: const Icon(Icons.key_rounded,
                                size: 18, color: Colors.blue),
                            label: Text('Clave',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Cerrar Sesión'),
                                content: const Text(
                                    '¿Estás seguro de que deseas salir?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancelar')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.red),
                                    child: const Text('Salir'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              if (context.mounted) Navigator.pop(context);
                              await AuthController.logout();
                            }
                          },
                          icon: const Icon(Icons.logout_rounded,
                              size: 18, color: Colors.red),
                          label: Text('Salir',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            _isDeletingAccount ? null : _openAccountAndPrivacy,
                        icon: _isDeletingAccount
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.manage_accounts_outlined),
                        label: Text(
                          _isDeletingAccount
                              ? 'Eliminando cuenta...'
                              : 'Cuenta y privacidad',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. NOTIFICACIONES
              _buildSectionTitle('NOTIFICACIONES'),
              NotificationCard(
                hasPermission: _hasPushPermission,
                isSupported: _pushSupported,
                unavailableMessage: _pushUnavailableMessage,
                onRequestPermission: _requestPushPermission,
              ),
              const SizedBox(height: 24),

              // 2.5 HISTORIAL DE AVISOS
              _buildSectionTitle('HISTORIAL DE AVISOS (ÚLTIMOS 6)'),
              _buildNotificationHistory(accentColor),
              const SizedBox(height: 24),

              _buildSectionTitle('ARCHIVOS Y MODO SIN CONEXIÓN'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      syncState.storageUnavailable
                          ? 'El almacenamiento está lleno. Aun así puedes abrir partituras con internet; se mantendrán temporalmente en memoria.'
                          : 'Comprueba el catálogo y vuelve a descargar partituras o MIDI faltantes, dañados o desactualizados.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: syncState.storageUnavailable
                            ? Colors.orange.shade700
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isRepairingFiles || syncState.isSyncing
                            ? null
                            : _repairFiles,
                        icon: _isRepairingFiles || syncState.isSyncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.build_circle_outlined),
                        label: Text(syncState.isSyncing
                            ? 'Actualizando archivos...'
                            : 'Reparar y actualizar archivos'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 3. COLOR DE ACENTO
              _buildSectionTitle('COLOR DE ACENTO'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildColorDot(AccentColorNotifier.defaultAccent,
                      selectedAccentColor), // Dorado
                  _buildColorDot(
                      const Color(0xFF3B82F6), selectedAccentColor), // Azul
                  _buildColorDot(
                      const Color(0xFF10B981), selectedAccentColor), // Verde
                  _buildColorDot(
                      const Color(0xFFEF4444), selectedAccentColor), // Carmesí
                  _buildColorDot(
                      const Color(0xFF8B5CF6), selectedAccentColor), // Púrpura
                  _buildColorDot(
                      const Color(0xFFF97316), selectedAccentColor), // Naranja
                  _buildColorDot(
                      const Color(0xFF06B6D4), selectedAccentColor), // Cian
                  _buildColorDot(
                      const Color(0xFFEC4899), selectedAccentColor), // Rosa
                  _buildColorDot(
                      const Color(0xFF6366F1), selectedAccentColor), // Índigo
                  _buildColorDot(
                      const Color(0xFF64748B), selectedAccentColor), // Plata
                  _buildColorDot(
                      const Color(0xFF8B5A2B), selectedAccentColor), // Café
                ],
              ),
              const SizedBox(height: 24),

              // 4. MODO PDF (SCROLL VS CAROUSEL)
              _buildSectionTitle('NAVEGACIÓN DE PARTITURA'),
              Row(
                children: [
                  Expanded(
                    child: _buildPdfNavOption(
                      title: 'Desplazamiento',
                      icon: Icons.swap_vert_rounded,
                      isSelected: !isCarousel,
                      onTap: () =>
                          ref.read(pdfNavModeProvider.notifier).set(false),
                      accentColor: accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPdfNavOption(
                      title: 'Carrusel',
                      icon: Icons.view_carousel_rounded,
                      isSelected: isCarousel,
                      onTap: () =>
                          ref.read(pdfNavModeProvider.notifier).set(true),
                      accentColor: accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 5. TEMAS
              _buildSectionTitle('PERFIL DE DISEÑO'),
              _buildThemeOption(
                context: context,
                title: 'Normal (Día/Noche)',
                icon: Icons.light_mode_rounded,
                isSelected: currentTheme == AppThemeMode.claro ||
                    currentTheme == AppThemeMode.oscuro ||
                    currentTheme == AppThemeMode.oscuroNormal,
                onTap: () =>
                    ref.read(themeProvider.notifier).setProfileNormal(),
                accentColor: accentColor,
              ),
              _buildThemeOption(
                context: context,
                title: 'Lectura (Sepia/Quiet)',
                icon: Icons.auto_stories_rounded,
                isSelected: currentTheme == AppThemeMode.sepia ||
                    currentTheme == AppThemeMode.quiet,
                onTap: () =>
                    ref.read(themeProvider.notifier).setProfileLectura(),
                accentColor: accentColor,
              ),
              _buildOledSwitch(
                enabled: useOledDarkMode,
                accentColor: accentColor,
                onChanged: (enabled) =>
                    ref.read(oledDarkModeProvider.notifier).set(enabled),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOledSwitch({
    required bool enabled,
    required Color accentColor,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: enabled
            ? accentColor.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled
              ? accentColor.withValues(alpha: 0.65)
              : theme.colorScheme.outline.withValues(alpha: 0.45),
        ),
      ),
      child: SwitchListTile.adaptive(
        value: enabled,
        onChanged: onChanged,
        activeColor: accentColor,
        secondary: Icon(
          enabled ? Icons.contrast_rounded : Icons.dark_mode_rounded,
          color: enabled ? accentColor : theme.colorScheme.onSurfaceVariant,
        ),
        title: const Text(
          'Oscuro OLED',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          enabled
              ? 'Negro puro para pantallas OLED'
              : 'Oscuro normal azul grisáceo',
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildColorDot(Color color, Color selectedColor) {
    final isSelected = color.toARGB32() == selectedColor.toARGB32();
    return GestureDetector(
      onTap: () => ref.read(accentColorProvider.notifier).set(color),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface, width: 3)
              : null,
          boxShadow: [
            if (isSelected)
              BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2)
          ],
        ),
        child: isSelected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  Widget _buildPdfNavOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required Color accentColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? accentColor : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => RotationTransition(
                  turns: Tween(begin: 0.9, end: 1.0).animate(anim),
                  child: FadeTransition(opacity: anim, child: child)),
              child: Icon(icon,
                  key: ValueKey(isSelected),
                  color: isSelected ? accentColor : Colors.grey),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? accentColor : Colors.grey,
              ),
              child: Text(title),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required Color accentColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? accentColor : Colors.grey.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? accentColor.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => RotationTransition(
                  turns: Tween(begin: 0.9, end: 1.0).animate(anim),
                  child: FadeTransition(opacity: anim, child: child)),
              child: Icon(icon,
                  key: ValueKey(isSelected),
                  color: isSelected ? accentColor : Colors.grey,
                  size: 20),
            ),
            const SizedBox(width: 16),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: GoogleFonts.inter(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? accentColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
              child: Text(title),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child)),
              child: isSelected
                  ? Icon(Icons.check_circle_rounded,
                      key: const ValueKey('check'),
                      color: accentColor,
                      size: 20)
                  : const SizedBox(
                      key: ValueKey('empty'), width: 20, height: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationHistory(Color accentColor) {
    if (_loadingNotifications) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (_lastNotifications.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            'No hay avisos recientes.',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _lastNotifications.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: Colors.grey.withValues(alpha: 0.15),
        ),
        itemBuilder: (context, index) {
          final aviso = _lastNotifications[index];
          final mensaje = aviso['mensaje'] as String? ?? '';
          final tipo = aviso['tipo'] as String? ?? 'RECORDATORIO';
          final creadoEn = aviso['creado_en'] as String? ?? '';

          final metadata = aviso['metadata'] as Map<String, dynamic>?;
          final cantoId = metadata?['id_canto'];
          final esVivo = tipo == 'VIVO';

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: esVivo
                  ? Colors.red.withValues(alpha: 0.1)
                  : accentColor.withValues(alpha: 0.1),
              child: Icon(
                esVivo ? Icons.live_tv_rounded : Icons.campaign_rounded,
                size: 14,
                color: esVivo ? Colors.red : accentColor,
              ),
            ),
            title: Text(
              mensaje,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight:
                    cantoId != null ? FontWeight.w600 : FontWeight.normal,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatFecha(creadoEn),
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
                ),
                if (cantoId != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              ],
            ),
            onTap: cantoId != null
                ? () {
                    // Cerrar diálogo de ajustes
                    Navigator.pop(context);
                    // Navegar al visor del canto
                    context.push('/visor/$cantoId');
                  }
                : null,
          );
        },
      ),
    );
  }
}
