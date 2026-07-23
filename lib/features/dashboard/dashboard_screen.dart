import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/core/providers/theme_provider.dart';
import 'package:repertorio_bc/core/realtime/realtime_manager.dart';
import 'package:repertorio_bc/features/dashboard/widgets/score_card.dart';
import 'package:repertorio_bc/features/dashboard/widgets/app_drawer.dart';
import 'package:repertorio_bc/core/offline/sync_manager.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'package:repertorio_bc/core/notifications/push_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.requestPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoadingAuth = ref.watch(authLoadingProvider);
    if (isLoadingAuth) {
      return Scaffold(backgroundColor: Theme.of(context).scaffoldBackgroundColor);
    }

    // Inicializar el RealtimeManager para que escuche cambios en BD
    ref.watch(realtimeManagerProvider);
    // Forzar inicio de la sincronización y descarga de archivos (PDF/MIDI) al iniciar la app
    ref.watch(syncManagerProvider);
    
    final cantosAsync = ref.watch(cantosFiltradosProvider);
    final cantos = cantosAsync.value ?? [];
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Quitar el Splash Screen una vez que terminaron de cargar los cantos iniciales
    final isLoadingBase = ref.watch(cantosBaseProvider).isLoading;
    if (!isLoadingBase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FlutterNativeSplash.remove();
      });
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(), // Sidebar idéntico a la PWA
      body: SafeArea(
        child: Column(
          children: [
            // Cabecera idéntica a la PWA
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  Builder(
                    builder: (context) => IconButton(
                      icon: Icon(Icons.menu_rounded, color: theme.colorScheme.onSurface),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 48,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          ref.read(searchTextProvider.notifier).set(val);
                          setState(() {}); // Forzar rebuild para mostrar/ocultar el botón X
                        },
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'Buscar canto por título...',
                          hintStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 20, color: Colors.grey),
                                  onPressed: () {
                                    _searchController.clear();
                                    ref.read(searchTextProvider.notifier).set('');
                                    setState(() {});
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      color: theme.colorScheme.onSurface,
                    ),
                    onPressed: () {
                      ref.read(themeProvider.notifier).toggleDayNight();
                    },
                  ),
                ],
              ),
            ),
            
            // Lista Vertical de Cantos
            Expanded(
              child: ref.watch(cantosBaseProvider).isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                    )
                  : cantos.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) => RefreshIndicator(
                            onRefresh: () async {},
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.library_music_rounded, size: 64, color: Colors.grey.withOpacity(0.3)),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Aún no hay partituras asignadas',
                                          style: GoogleFonts.inter(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 16),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Tu director debe añadir cantos a tu coro.',
                                          style: GoogleFonts.inter(color: Colors.grey, fontWeight: FontWeight.w400, fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      physics: const BouncingScrollPhysics(),
                      itemCount: cantos.length,
                      itemBuilder: (context, index) {
                        final canto = cantos[index];
                        return ScoreCard(
                          canto: canto,
                          index: index,
                          onTap: () => context.push('/visor/${canto.id}'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms, curve: Curves.easeOut);
  }
}
