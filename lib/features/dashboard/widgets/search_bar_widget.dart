import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:repertorio_bc/core/providers/theme_provider.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';

class SearchBarWidget extends ConsumerWidget {
  const SearchBarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeProvider);
    final isSepia = themeMode == AppThemeMode.sepia;

    return Container(
      decoration: BoxDecoration(
        color: isSepia ? theme.colorScheme.onSurface.withOpacity(0.05) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSepia ? theme.colorScheme.onSurface.withOpacity(0.1) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: TextField(
        onChanged: (val) {
          ref.read(searchTextProvider.notifier).set(val);
        },
        style: GoogleFonts.inter(fontSize: 16, color: theme.colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: 'Buscar por título...',
          hintStyle: GoogleFonts.inter(color: theme.colorScheme.onSurface.withOpacity(0.5)),
          prefixIcon: Icon(Icons.search_rounded, color: theme.colorScheme.primary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
