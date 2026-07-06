import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:flutter/foundation.dart';

// Provider global para inyectar y manejar el ciclo de vida del RealtimeManager
final realtimeManagerProvider = Provider<RealtimeManager>((ref) {
  final manager = RealtimeManager(ref);
  
  // Escuchar cambios de sesión. Si el perfil cambia o se cierra sesión, nos reconectamos o desconectamos.
  ref.listen(perfilProvider, (previous, next) {
    if (next.value != null) {
      manager.conectar(next.value!.coroId);
    } else {
      manager.desconectar();
    }
  });

  ref.onDispose(() {
    manager.desconectar();
  });

  return manager;
});

class RealtimeManager {
  final Ref ref;
  RealtimeChannel? _mainChannel;
  RealtimeChannel? _avisosChannel;
  String? _sedeActual;

  RealtimeManager(this.ref);

  void conectar(String coroId) {
    if (_sedeActual == coroId && _mainChannel != null) return;
    
    _sedeActual = coroId;
    desconectar(); // Limpiar si había una conexión previa

    debugPrint('📡 Realtime: Sincronizando sede [$_sedeActual]...');

    _mainChannel = SupabaseService.client.channel('main-$_sedeActual')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cantos',
          callback: (payload) => _onRepertorioChanged(payload))
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cantos_coros',
          callback: (payload) => _onRepertorioChanged(payload))
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'eventos',
          callback: (payload) {
            // Manejo de DELETE
            final row = payload.eventType == PostgresChangeEvent.delete ? payload.oldRecord : payload.newRecord;
            if (row['coro_id'] != _sedeActual && row['coro_id'] != 'estatal') return;
            _onEventosChanged(payload);
          })
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'eventos_cantos',
          callback: (payload) => _onEventosChanged(payload))
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'perfiles',
          callback: (payload) => _onMiembrosChanged(payload))
      ..subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('✅ Realtime: Sincronía Activa');
        }
      });

    _avisosChannel = SupabaseService.client.channel('avisos-$_sedeActual')
      ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'avisos',
          callback: (payload) {
            final row = payload.newRecord;
            if (row['coro_id'] == _sedeActual || row['coro_id'] == 'estatal') {
              _onAvisoReceived(row, isEstatal: row['coro_id'] == 'estatal');
            }
          })
      ..subscribe();
  }

  void desconectar() {
    if (_mainChannel != null || _avisosChannel != null) {
      debugPrint('🔌 Realtime: Desconectando canales...');
      SupabaseService.client.removeAllChannels();
      _mainChannel = null;
      _avisosChannel = null;
      _sedeActual = null;
    }
  }

  // --- CALLBACKS ---

  void _onRepertorioChanged(PostgresChangePayload payload) {
    debugPrint('🔄 Realtime: Cambio detectado en el repertorio. Refrescando...');
    // Invalidamos el Provider base. Riverpod automáticamente volverá a descargar
    // el catálogo en segundo plano y actualizará la UI sin bloqueos.
    ref.invalidate(cantosBaseProvider);
  }

  void _onEventosChanged(PostgresChangePayload payload) {
    debugPrint('🔄 Realtime: Cambio detectado en eventos.');
    // TODO: ref.invalidate(eventosProvider) cuando se cree en la Fase 6
  }

  void _onMiembrosChanged(PostgresChangePayload payload) {
    debugPrint('🔄 Realtime: Cambio detectado en miembros.');
    // TODO: ref.invalidate(miembrosProvider) cuando se cree en la Fase 6
  }

  void _onAvisoReceived(Map<String, dynamic> aviso, {required bool isEstatal}) {
    debugPrint('🔔 Realtime: Nuevo aviso recibido -> ${aviso['mensaje']}');
    // TODO: Mostrar un SnackBar global o un Toast personalizado
  }
}
