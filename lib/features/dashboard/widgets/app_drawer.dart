import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/core/providers/eventos_provider.dart';
import 'package:repertorio_bc/core/offline/sync_manager.dart';
import 'package:repertorio_bc/features/settings/settings_screen.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cantosBase = ref.watch(cantosDeLaSedeProvider);
    final cantosFiltradosAsync = ref.watch(cantosFiltradosProvider);
    final cantosFiltrados = cantosFiltradosAsync.value ?? [];
    final carpetasEspeciales = ref.watch(eventosPermanentesProvider);
    
    // Identificar gestor para agregar el botón extra
    final perfil = ref.watch(perfilProvider).value;
    final isGestor = perfil != null && ['director', 'estatal', 'superadmin'].contains(perfil.rol);

    // Lista de temas dinámicos
    final temasUnicos = cantosBase
        .expand((c) => c.temas)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // LOGO SIDEBAR
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Repertorio',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${cantosFiltrados.length}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Indicador de Sincronización Offline (Movido arriba)
            Consumer(
              builder: (context, ref, child) {
                final syncState = ref.watch(syncManagerProvider);
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            syncState.isSyncing ? Icons.sync_rounded : Icons.cloud_done_rounded,
                            size: 14,
                            color: syncState.isSyncing ? theme.colorScheme.secondary : Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              syncState.isSyncing 
                                  ? 'Sincronizando (${(syncState.progress * 100).toInt()}%)'
                                  : 'Disponible Offline',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: syncState.isSyncing ? theme.colorScheme.secondary : Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (syncState.isSyncing) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: syncState.progress,
                          backgroundColor: theme.colorScheme.secondary.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation(theme.colorScheme.secondary),
                          borderRadius: BorderRadius.circular(10),
                          minHeight: 3,
                        ),
                      ]
                    ],
                  ),
                );
              },
            ),

            // SCROLL AREA (Carpetas + Temas)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  // CARPETAS
                  _buildSectionLabel('CARPETAS'),
                  _buildSidebarBtn(
                    context: context,
                    ref: ref,
                    id: 'local',
                    label: 'CORO LOCAL',
                  ),
                  _buildSidebarBtn(
                    context: context,
                    ref: ref,
                    id: 'estatal',
                    label: 'CORO ESTATAL',
                  ),
                  
                  // MIS CARPETAS
                  if (carpetasEspeciales.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildSectionLabel('MIS CARPETAS'),
                    ...carpetasEspeciales.map((c) => _buildSidebarBtn(
                          context: context,
                          ref: ref,
                          id: 'evento_${c.id}',
                          label: c.nombre.toUpperCase(),
                        )),
                  ],
                  
                  const SizedBox(height: 10),
                  
                  // TEMAS
                  if (temasUnicos.isNotEmpty) ...[
                    _buildSectionLabel('FILTRAR POR TEMA'),
                    ...temasUnicos.map((tema) => _buildSidebarBtn(
                          context: context,
                          ref: ref,
                          id: 'tema_$tema',
                          label: tema.toUpperCase(),
                          isTema: true,
                        )),
                  ],
                ],
              ),
            ),

            // FOOTER (Ajustes)
            Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
              ),
              padding: const EdgeInsets.only(bottom: 10, top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionLabel('CONFIGURACIÓN'),
                  _buildFooterBtn(
                    context: context,
                    icon: Icons.settings_rounded,
                    label: 'AJUSTES DE LA APP',
                    onTap: () {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (context) => const SettingsDialog(),
                      );
                    },
                  ),
                  if (isGestor)
                    _buildFooterBtn(
                      context: context,
                      icon: Icons.admin_panel_settings_rounded,
                      label: 'GESTOR ADMIN',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/gestor');
                      },
                    ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSidebarBtn({
    required BuildContext context,
    required WidgetRef ref,
    required String id,
    required String label,
    bool isTema = false,
  }) {
    final activeCategory = ref.watch(categoryFilterProvider);
    final isActive = activeCategory == id;
    final theme = Theme.of(context);

    // En PWA los botones no tienen padding horizontal externo, sino interno
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
      child: InkWell(
        onTap: () {
          ref.read(categoryFilterProvider.notifier).set(id);
          Navigator.pop(context); // Cierra sidebar (comportamiento móvil web)
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isActive ? theme.colorScheme.secondary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isActive 
              ? [BoxShadow(color: theme.colorScheme.secondary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterBtn({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.7)),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
