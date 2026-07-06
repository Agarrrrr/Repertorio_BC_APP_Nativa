import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Las credenciales anon/publicas de Supabase
  static const String _supabaseUrl = 'https://mxnhmtztxgeccohlgqpt.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im14bmhtdHp0eGdlY2NvaGxncXB0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3OTcxMDMsImV4cCI6MjA5MjM3MzEwM30.xoqintNQy_mX02uX4kVuFmv-JCrQeBAWmqBvzBGcR1M';

  // Almacenamiento R2 (para PDFs y MIDI)
  static const String storageUrl = 'https://repertoriobc-files.huritolentino.workers.dev';

  static Future<void> init() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
      // Opcional: configuracion de realtime y auth persistence se maneja por defecto en supabase_flutter
    );
  }

  // Getter rapido para la instancia del cliente
  static SupabaseClient get client => Supabase.instance.client;
}
