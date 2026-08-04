import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/core/notifications/push_service.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/core/activity/activity_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final realtimeManagerProvider = Provider<RealtimeManager>((ref) {
  final manager = RealtimeManager(ref);
  final currentProfile = ref.read(perfilProvider).value;
  if (currentProfile != null) manager.connect(currentProfile.coroId);

  ref.listen(perfilProvider, (previous, next) {
    final profile = next.value;
    if (profile == null) {
      manager.disconnect();
    } else {
      manager.connect(profile.coroId);
    }
  });
  ref.onDispose(manager.disconnect);
  return manager;
});

class RealtimeManager {
  RealtimeManager(this.ref);

  final Ref ref;
  RealtimeChannel? _mainChannel;
  RealtimeChannel? _alertsChannel;
  String? _currentSede;

  void conectar(String coroId) => connect(coroId);
  void desconectar() => disconnect();

  void connect(String coroId) {
    if (coroId.isEmpty) return;
    if (_currentSede == coroId && _mainChannel != null) return;

    // Remove the previous channels before assigning the next context. The old
    // implementation did this in reverse and reset the newly selected sede.
    disconnect();
    _currentSede = coroId;

    final main = SupabaseService.client.channel('main-$coroId');
    main
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'cantos',
        callback: _onRepertoireChanged,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'cantos_coros',
        callback: _onRepertoireChanged,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'eventos',
        callback: (payload) {
          final row = payload.eventType == PostgresChangeEvent.delete
              ? payload.oldRecord
              : payload.newRecord;
          if (row['coro_id'] == coroId || row['coro_id'] == 'estatal') {
            debugPrint('[Realtime] Evento actualizado.');
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'eventos_cantos',
        callback: (_) =>
            debugPrint('[Realtime] Contenido de evento actualizado.'),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'perfiles',
        callback: (_) => debugPrint('[Realtime] Miembros actualizados.'),
      )
      ..subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await main.track({
            'user_id': SupabaseService.client.auth.currentUser?.id,
            'sede': coroId,
            'plataforma': ActivityService.platform,
            'online_at': DateTime.now().toUtc().toIso8601String(),
          });
          debugPrint('[Realtime] Sede $coroId conectada.');
        }
      });
    _mainChannel = main;

    final alerts = SupabaseService.client.channel('avisos-$coroId');
    alerts
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'avisos',
        callback: (payload) {
          final row = payload.newRecord;
          if (row['coro_id'] == coroId || row['coro_id'] == 'estatal') {
            final mensaje = row['mensaje']?.toString() ?? '';
            final tipo = row['tipo']?.toString() ?? '';
            final metadata = row['metadata'] as Map<String, dynamic>?;
            final cantoId = metadata?['canto_id']?.toString();

            debugPrint('[Realtime] Nuevo aviso: $mensaje');
            ref.invalidate(cantosBaseProvider);

            if (tipo == 'NUEVO_CANTO' || mensaje.toLowerCase().contains('nuevo canto')) {
              PushService.showNotification(
                title: '🎵 Nuevo canto en el repertorio',
                body: mensaje,
                payload: cantoId != null ? 'visor_$cantoId' : null,
              );
            } else if (tipo == 'RECORDATORIO') {
              PushService.showNotification(
                title: '📢 Aviso del Gestor',
                body: mensaje,
              );
            }
          }
        },
      )
      ..subscribe();
    _alertsChannel = alerts;
  }

  void disconnect() {
    final main = _mainChannel;
    final alerts = _alertsChannel;
    _mainChannel = null;
    _alertsChannel = null;
    _currentSede = null;
    if (main != null) SupabaseService.client.removeChannel(main);
    if (alerts != null) SupabaseService.client.removeChannel(alerts);
  }

  void _onRepertoireChanged(PostgresChangePayload payload) {
    ref.invalidate(cantosBaseProvider);
  }
}
