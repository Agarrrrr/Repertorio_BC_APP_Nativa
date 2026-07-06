import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';

class CarpetaEspecial {
  final String id;
  final String nombre;

  CarpetaEspecial({required this.id, required this.nombre});

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre};
  factory CarpetaEspecial.fromJson(Map<String, dynamic> json) => CarpetaEspecial(
        id: json['id'],
        nombre: json['nombre'],
      );
}

class EventosPermanentesNotifier extends Notifier<List<CarpetaEspecial>> {
  @override
  List<CarpetaEspecial> build() {
    _loadFromHive();
    return state;
  }

  void _loadFromHive() {
    final box = Hive.box('cache');
    final data = box.get('eventos_permanentes');
    if (data != null) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        final carpetas = decoded.map((e) => CarpetaEspecial.fromJson(e as Map<String, dynamic>)).toList();
        state = carpetas;
      } catch (e) {
        debugPrint('Error loading carpetas: $e');
        state = [];
      }
    } else {
      state = [];
    }
  }

  void _saveToHive(List<CarpetaEspecial> carpetas) {
    final box = Hive.box('cache');
    box.put('eventos_permanentes', jsonEncode(carpetas.map((e) => e.toJson()).toList()));
  }

  Future<void> eliminarCarpeta(String id) async {
    final newList = state.where((e) => e.id != id).toList();
    state = newList;
    _saveToHive(newList);
    
    // Remover de Supabase user_metadata
    try {
      final session = SupabaseService.client.auth.currentSession;
      if (session != null) {
        final meta = session.user.userMetadata ?? {};
        final nube = List<Map<String, dynamic>>.from(meta['eventos_permanentes'] ?? []);
        nube.removeWhere((e) => e['id'] == id);
        await SupabaseService.client.auth.updateUser(
          UserAttributes(data: {'eventos_permanentes': nube}),
        );
      }
    } catch (e) {
      debugPrint('Error removiendo de la nube: $e');
    }
  }

  Future<bool> manejarLinkEvento(String idEvento) async {
    try {
      // 1. Descargar info de Supabase
      final evData = await SupabaseService.client
          .from('eventos')
          .select('id, nombre, miembros_participantes')
          .eq('id', idEvento)
          .maybeSingle();

      if (evData == null) return false;

      final String evId = evData['id'];
      final String evNombre = evData['nombre'];
      
      // 2. Agregar localmente si no existe
      if (!state.any((e) => e.id == evId)) {
        final nuevaCarpeta = CarpetaEspecial(id: evId, nombre: evNombre);
        final newList = [...state, nuevaCarpeta];
        state = newList;
        _saveToHive(newList);

        // 3. Sincronizar historial en la nube
        try {
          final session = SupabaseService.client.auth.currentSession;
          if (session != null) {
            final meta = session.user.userMetadata ?? {};
            final nube = List<Map<String, dynamic>>.from(meta['eventos_permanentes'] ?? []);
            if (!nube.any((e) => e['id'] == evId)) {
              nube.add({'id': evId, 'nombre': evNombre});
              await SupabaseService.client.auth.updateUser(
                UserAttributes(data: {'eventos_permanentes': nube}),
              );
            }
          }
        } catch (e) {
          debugPrint('Error sincronizando historial nube: $e');
        }
      }

      // 4. Inyectar UUID en miembros_participantes si es privada
      try {
        final session = SupabaseService.client.auth.currentSession;
        if (session != null) {
          final currentMembers = List<String>.from(evData['miembros_participantes'] ?? []);
          final esPrivada = currentMembers.isNotEmpty;
          if (esPrivada && !currentMembers.contains(session.user.id)) {
            currentMembers.add(session.user.id);
            await SupabaseService.client
                .from('eventos')
                .update({'miembros_participantes': currentMembers})
                .eq('id', evId);
          }
        }
      } catch (e) {
        debugPrint('Error vinculando pase de invitado: $e');
      }

      return true;
    } catch (e) {
      debugPrint('Error procesando link de evento: $e');
      return false;
    }
  }
}

final eventosPermanentesProvider = NotifierProvider<EventosPermanentesNotifier, List<CarpetaEspecial>>(EventosPermanentesNotifier.new);
