import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NotificationCard extends StatelessWidget {
  final bool hasPermission;
  final bool isSupported;
  final String? unavailableMessage;
  final VoidCallback onRequestPermission;

  const NotificationCard({
    super.key,
    required this.hasPermission,
    this.isSupported = true,
    this.unavailableMessage,
    required this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasPermission
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasPermission
              ? Colors.green.withOpacity(0.3)
              : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasPermission
                ? Icons.notifications_active_rounded
                : isSupported
                    ? Icons.notifications_off_rounded
                    : Icons.phonelink_erase_rounded,
            color: hasPermission ? Colors.green : Colors.red,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPermission
                      ? 'Notificaciones activas'
                      : isSupported
                          ? 'Notificaciones desactivadas'
                          : 'No disponibles en este dispositivo',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: hasPermission
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
                if (!isSupported && unavailableMessage != null)
                  Text(
                    unavailableMessage!,
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          if (!hasPermission && isSupported)
            TextButton(
              onPressed: onRequestPermission,
              child: const Text('ACTIVAR'),
            )
        ],
      ),
    );
  }
}
