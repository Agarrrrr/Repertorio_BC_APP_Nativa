import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/models/canto.dart';
import 'package:repertorio_bc/core/pdf/pdf_engine.dart';
import 'package:repertorio_bc/core/offline/sync_manager.dart';

class ScoreCard extends ConsumerWidget {
  final Canto canto;
  final int index;
  final VoidCallback onTap;

  const ScoreCard({
    super.key,
    required this.canto,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDeclaredMidi =
        canto.midiArchivo != null && canto.midiArchivo!.isNotEmpty;
    final missingPdf = ref.watch(
      syncManagerProvider.select((s) => s.failedPdfCantoIds.contains(canto.id)),
    );
    final missingMidi = ref.watch(
      syncManagerProvider
          .select((s) => s.failedMidiCantoIds.contains(canto.id)),
    );
    final isReadyPdf = ref.watch(
      syncManagerProvider
          .select((s) => s.readyPdfCantoIds.contains(canto.id)),
    );
    final hasAudio = hasDeclaredMidi && !missingMidi;

    final cardBg = (missingPdf || missingMidi)
        ? (isDark ? const Color(0xFF35191B) : const Color(0xFFFFEBEE))
        : Theme.of(context).colorScheme.surface;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            boxShadow: [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              )
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onTap,
              onHighlightChanged: (isHighlighted) {
                if (isHighlighted) {
                  // 🚀 PREFETCH: Iniciar carga del PDF y resolución de rutas en el momento del toque
                  ref.read(pdfEngineProvider.notifier).init(canto);
                }
              },
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: EdgeInsets.zero,
                child: Ink(
                  decoration: BoxDecoration(
                    color: (missingPdf || missingMidi)
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                          topRight: Radius.circular(17),
                          bottomRight: Radius.circular(17),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            // Texto
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    canto.nombre,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: (missingPdf || missingMidi)
                                          ? (isDark
                                              ? Colors.red.shade200
                                              : Colors.red.shade900)
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      if (missingPdf || missingMidi) ...[
                                        const Icon(
                                          Icons.error_outline_rounded,
                                          size: 13,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Falta archivo · ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ] else if (isReadyPdf) ...[
                                        Icon(
                                          Icons.offline_pin_rounded,
                                          size: 13,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      if (hasAudio) ...[
                                        Icon(Icons.piano_rounded,
                                            size: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                        const SizedBox(width: 4),
                                      ],
                                      Flexible(
                                        child: Text(
                                          canto.temas.isEmpty
                                              ? 'Sin categoría'
                                              : canto.temas.join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Flecha
                            Icon(
                              Icons.chevron_right_rounded,
                              color: isDark
                                  ? Colors.white30
                                  : const Color(0xFFCBD5E1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
