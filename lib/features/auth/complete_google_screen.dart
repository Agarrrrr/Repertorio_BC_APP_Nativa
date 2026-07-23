import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';

class CompleteGoogleScreen extends ConsumerStatefulWidget {
  const CompleteGoogleScreen({super.key});

  @override
  ConsumerState<CompleteGoogleScreen> createState() => _CompleteGoogleScreenState();
}

class _CompleteGoogleScreenState extends ConsumerState<CompleteGoogleScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _corosList = [];
  List<String> _municipios = [];
  String? _selectedMunicipio;
  String? _selectedCoroId;

  @override
  void initState() {
    super.initState();
    _fetchCoros();
  }

  Future<void> _fetchCoros() async {
    try {
      final data = await Supabase.instance.client
          .from('coros')
          .select('id, nombre, municipio')
          .neq('nombre', 'Estatal')
          .neq('nombre', 'Sin sede');
      
      final list = List<Map<String, dynamic>>.from(data);
      final m = list.map((e) => e['municipio'] as String).toSet().toList();
      m.sort();

      if (mounted) {
        setState(() {
          _corosList = list;
          _municipios = m;
        });
      }
    } catch (e) {
      debugPrint("Error al cargar coros: $e");
    }
  }

  Future<void> _completeRegistration() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.isEmpty || _selectedCoroId == null) {
      setState(() => _errorMessage = "Por favor, completa todos los campos requeridos.");
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = "Las contraseñas no coinciden.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("Sesión inválida");

      // Set password for future email logins
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password)
      );

      // Create profile in perfiles with estado = activo
      final nombre = user.userMetadata?['full_name'] ?? 'Usuario Google';
      await Supabase.instance.client.from('perfiles').insert({
        'id': user.id,
        'email': user.email,
        'nombre': nombre,
        'coro_id': _selectedCoroId,
        'voz': 'sin_asignar',
        'estado': 'activo',
        'rol': 'miembro',
      });

      // Refrescar perfil
      ref.invalidate(perfilProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cuenta configurada exitosamente.', style: GoogleFonts.inter()),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().contains('already exists') 
              ? 'Este usuario ya tiene perfil.' 
              : 'Error: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final corosFiltrados = _corosList.where((c) => c['municipio'] == _selectedMunicipio).toList();

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF001533), Color(0xFF0033A0), Color(0xFF0F52BA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.g_mobiledata_rounded,
                            size: 72,
                            color: Colors.white.withValues(alpha: 0.9),
                          ).animate().fade().scale(),
                          const SizedBox(height: 12),
                          Text(
                            'Último paso',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ).animate().fade().slideY(),
                          const SizedBox(height: 8),
                          Text(
                            'Completa tus datos para finalizar el registro.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ).animate().fade(),
                          const SizedBox(height: 24),

                          if (_errorMessage != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                              ),
                              child: Text(_errorMessage!, style: GoogleFonts.inter(color: Colors.white)),
                            ),

                          _buildDropdown(
                            hint: 'Municipio / Área',
                            icon: Icons.map_rounded,
                            value: _selectedMunicipio,
                            items: _municipios.map((m) => DropdownMenuItem(value: m, child: Text(m, style: GoogleFonts.inter(color: Colors.white)))).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedMunicipio = val;
                                _selectedCoroId = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),

                          _buildDropdown(
                            hint: 'Sede / Iglesia',
                            icon: Icons.church_rounded,
                            value: _selectedCoroId,
                            items: corosFiltrados.map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['nombre'] as String, style: GoogleFonts.inter(color: Colors.white)))).toList(),
                            onChanged: _selectedMunicipio == null ? null : (val) => setState(() => _selectedCoroId = val),
                          ),
                          const SizedBox(height: 16),

                          _buildTextField(
                            controller: _passwordController,
                            hintText: 'Establecer Contraseña',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.white70),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          _buildTextField(
                            controller: _confirmController,
                            hintText: 'Confirmar Contraseña',
                            icon: Icons.lock_reset_rounded,
                            obscureText: _obscurePassword,
                          ),
                          const SizedBox(height: 32),

                          Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFD4AF37), Color(0xFFAA8000)]),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _completeRegistration,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                                  : Text('Finalizar', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF001533))),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          TextButton(
                            onPressed: () {
                              AuthController.logout();
                              context.go('/login');
                            },
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
        cursorColor: Colors.white70,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.inter(color: Colors.white54, fontSize: 15),
          prefixIcon: Icon(icon, color: Colors.white70, size: 22),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String hint,
    required IconData icon,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 22),
              const SizedBox(width: 12),
              Text(hint, style: GoogleFonts.inter(color: Colors.white54, fontSize: 15)),
            ],
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
          isExpanded: true,
          dropdownColor: const Color(0xFF001533),
          style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
