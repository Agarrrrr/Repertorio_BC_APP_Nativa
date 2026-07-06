import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _corosList = [];
  List<String> _municipios = [];
  String? _selectedMunicipio;
  String? _selectedCoroId;
  String? _selectedVoz;

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

  Future<void> _register() async {
    final nombre = _nombreController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (nombre.isEmpty || email.isEmpty || password.isEmpty || 
        _selectedCoroId == null || _selectedVoz == null) {
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
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: 'repertoriobc://login-callback/',
        data: {
          'nombre': nombre,
          'coro_id': _selectedCoroId,
          'voz': _selectedVoz,
        }
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cuenta creada exitosamente. ¡Bienvenido a tu Sede!', style: GoogleFonts.inter()),
            backgroundColor: Colors.green,
          ),
        );
        // El router reaccionará automáticamente al cambio de sesión de Supabase
        // y mandará al usuario directamente al Dashboard (Sede).
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = "Error al crear la cuenta. Inténtalo más tarde.");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filtramos coros basado en el municipio seleccionado
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
                constraints: const BoxConstraints(maxWidth: 400),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
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
                            Icons.person_add_alt_1_rounded,
                            size: 56,
                            color: Colors.white.withValues(alpha: 0.9),
                          ).animate().fade().scale(),
                          const SizedBox(height: 12),
                          Text(
                            'Solicitar Acceso',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ).animate().fade().slideY(),
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

                          _buildTextField(
                            controller: _nombreController,
                            hintText: 'Nombre completo',
                            icon: Icons.person_outline_rounded,
                          ),
                          const SizedBox(height: 16),
                          
                          _buildTextField(
                            controller: _emailController,
                            hintText: 'Email',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          
                          _buildTextField(
                            controller: _passwordController,
                            hintText: 'Contraseña',
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
                          const SizedBox(height: 16),

                          _buildDropdown(
                            hint: 'Municipio / Área',
                            icon: Icons.map_rounded,
                            value: _selectedMunicipio,
                            items: _municipios.map((m) => DropdownMenuItem(value: m, child: Text(m, style: GoogleFonts.inter(color: Colors.white)))).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedMunicipio = val;
                                _selectedCoroId = null; // reset coro
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

                          _buildDropdown(
                            hint: 'Tu Voz',
                            icon: Icons.mic_none_rounded,
                            value: _selectedVoz,
                            items: const [
                              DropdownMenuItem(value: 'soprano', child: Text('Soprano', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: 'contralto', child: Text('Contralto', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: 'tenor', child: Text('Tenor', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: 'bajo', child: Text('Bajo', style: TextStyle(color: Colors.white))),
                            ],
                            onChanged: (val) => setState(() => _selectedVoz = val),
                          ),
                          
                          const SizedBox(height: 32),
                          
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFDF00), Color(0xFFD4AF37)],
                              ),
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _register,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : Text(
                                      'Crear solicitud',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF001F54),
                                      ),
                                    ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => context.pop(),
                            child: Text(
                              'Volver al inicio',
                              style: GoogleFonts.inter(color: Colors.white70, fontWeight: FontWeight.w600),
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
    required ValueChanged<String?>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
          isExpanded: true,
          dropdownColor: const Color(0xFF001F54),
          items: items,
          onChanged: onChanged,
          selectedItemBuilder: (context) {
            return items.map((e) {
              return Row(
                children: [
                  Icon(icon, color: Colors.white70, size: 22),
                  const SizedBox(width: 12),
                  Text(e.value ?? '', style: GoogleFonts.inter(color: Colors.white, fontSize: 15)),
                ],
              );
            }).toList();
          }
        ),
      ),
    );
  }
}
