import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:repertorio_bc/core/providers/theme_provider.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/features/settings/notification_card.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  bool _hasPushPermission = false;
  List<Map<String, dynamic>> _lastNotifications = [];
  bool _loadingNotifications = true;
  bool _isInit = false;

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

    final box = Hive.box('cache');
    final cached = box.get('avisos_json');
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
      
      box.put('avisos_json', jsonEncode(res));

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
      if (date.year == now.year && date.month == now.month && date.day == now.day) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      return '${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _checkPushPermission() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    setState(() {
      _hasPushPermission = settings.authorizationStatus == AuthorizationStatus.authorized;
    });
  }

  Future<void> _requestPushPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    setState(() {
      _hasPushPermission = settings.authorizationStatus == AuthorizationStatus.authorized;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTheme = ref.watch(themeProvider);
    final accentColor = ref.watch(accentColorProvider);
    final isCarousel = ref.watch(pdfNavModeProvider);
    
    // Auth Data
    final user = ref.watch(authUserProvider).value;
    final perfil = ref.watch(perfilProvider).value;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                    icon: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurface),
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
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.isAnonymous == true ? 'Cuenta de Invitado' : (user?.email ?? 'Cargando...'),
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
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
                                            keyboardType: TextInputType.emailAddress,
                                            decoration: const InputDecoration(labelText: 'Correo Electrónico'),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: passCtrl,
                                            obscureText: true,
                                            decoration: const InputDecoration(labelText: 'Contraseña'),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                        TextButton(
                                          onPressed: () async {
                                            if (emailCtrl.text.isNotEmpty && passCtrl.text.isNotEmpty) {
                                              try {
                                                await SupabaseService.client.auth.updateUser(UserAttributes(email: emailCtrl.text, password: passCtrl.text));
                                                if (c.mounted) {
                                                  Navigator.pop(c, true);
                                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cuenta vinculada correctamente', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
                                                }
                                              } catch (e) {
                                                if (c.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                              }
                                            }
                                          }, 
                                          child: const Text('Vincular'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.link_rounded, size: 18, color: Colors.green),
                                label: Text('Vincular', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                          decoration: const InputDecoration(labelText: 'Nueva Contraseña'),
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: confirmCtrl,
                                          obscureText: true,
                                          decoration: const InputDecoration(labelText: 'Confirmar Contraseña'),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                      TextButton(
                                        onPressed: () async {
                                          if (passCtrl.text.isNotEmpty && passCtrl.text == confirmCtrl.text) {
                                            try {
                                              await SupabaseService.client.auth.updateUser(UserAttributes(password: passCtrl.text));
                                              if (c.mounted) {
                                                Navigator.pop(c, true);
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña actualizada', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
                                              }
                                            } catch (e) {
                                              if (c.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                            }
                                          } else {
                                            ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Las contraseñas no coinciden')));
                                          }
                                        }, 
                                        child: const Text('Guardar'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              icon: const Icon(Icons.key_rounded, size: 18, color: Colors.blue),
                              label: Text('Clave', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                    content: const Text('¿Estás seguro de que deseas salir?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                      TextButton(
                                        onPressed: () => Navigator.pop(c, true), 
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
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
                              icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.red),
                              label: Text('Salir', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),

              // 2. NOTIFICACIONES
              _buildSectionTitle('NOTIFICACIONES'),
              NotificationCard(
                hasPermission: _hasPushPermission,
                onRequestPermission: _requestPushPermission,
              ),
              const SizedBox(height: 24),

              // 2.5 HISTORIAL DE AVISOS
              _buildSectionTitle('HISTORIAL DE AVISOS (ÚLTIMOS 6)'),
              _buildNotificationHistory(accentColor),
              const SizedBox(height: 24),

              // 3. COLOR DE ACENTO
              _buildSectionTitle('COLOR DE ACENTO'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildColorDot(const Color(0xFFD4AF37), accentColor), // Dorado
                  _buildColorDot(const Color(0xFF3B82F6), accentColor), // Azul
                  _buildColorDot(const Color(0xFF10B981), accentColor), // Verde
                  _buildColorDot(const Color(0xFFEF4444), accentColor), // Carmesí
                  _buildColorDot(const Color(0xFF8B5CF6), accentColor), // Púrpura
                  _buildColorDot(const Color(0xFFF97316), accentColor), // Naranja
                  _buildColorDot(const Color(0xFF06B6D4), accentColor), // Cian (Teal)
                  _buildColorDot(const Color(0xFFEC4899), accentColor), // Rosa (Magenta)
                  _buildColorDot(const Color(0xFF6366F1), accentColor), // Índigo
                  _buildColorDot(const Color(0xFF64748B), accentColor), // Plata (Slate)
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
                      onTap: () => ref.read(pdfNavModeProvider.notifier).set(false),
                      accentColor: accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPdfNavOption(
                      title: 'Carrusel',
                      icon: Icons.view_carousel_rounded,
                      isSelected: isCarousel,
                      onTap: () => ref.read(pdfNavModeProvider.notifier).set(true),
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
                isSelected: currentTheme == AppThemeMode.claro || currentTheme == AppThemeMode.oscuro,
                onTap: () => ref.read(themeProvider.notifier).setProfileNormal(),
                accentColor: accentColor,
              ),
              _buildThemeOption(
                context: context,
                title: 'Lectura (Sepia/Quiet)',
                icon: Icons.auto_stories_rounded,
                isSelected: currentTheme == AppThemeMode.sepia || currentTheme == AppThemeMode.quiet,
                onTap: () => ref.read(themeProvider.notifier).setProfileLectura(),
                accentColor: accentColor,
              ),
            ],
          ),
        ),
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
          border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
          boxShadow: [
            if (isSelected) BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 2)
          ],
        ),
        child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
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
          color: isSelected ? accentColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => RotationTransition(turns: Tween(begin: 0.9, end: 1.0).animate(anim), child: FadeTransition(opacity: anim, child: child)),
              child: Icon(icon, key: ValueKey(isSelected), color: isSelected ? accentColor : Colors.grey),
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
            color: isSelected ? accentColor : Colors.grey.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? accentColor.withValues(alpha: 0.1) : Colors.transparent,
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => RotationTransition(turns: Tween(begin: 0.9, end: 1.0).animate(anim), child: FadeTransition(opacity: anim, child: child)),
              child: Icon(icon, key: ValueKey(isSelected), color: isSelected ? accentColor : Colors.grey, size: 20),
            ),
            const SizedBox(width: 16),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: GoogleFonts.inter(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? accentColor : Theme.of(context).colorScheme.onSurface,
              ),
              child: Text(title),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
              child: isSelected 
                  ? Icon(Icons.check_circle_rounded, key: const ValueKey('check'), color: accentColor, size: 20)
                  : const SizedBox(key: ValueKey('empty'), width: 20, height: 20),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: esVivo ? Colors.red.withValues(alpha: 0.1) : accentColor.withValues(alpha: 0.1),
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
                fontWeight: cantoId != null ? FontWeight.w600 : FontWeight.normal,
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
