import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  ConsumerState<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends ConsumerState<UpdatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscure = true;

  Future<void> _updatePassword() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.isEmpty) {
      setState(() => _errorMessage = "Por favor, ingresa una nueva contraseña.");
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
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      
      if (mounted) {
        // Limpiamos el flag de recuperacion
        ref.read(isRecoveringPasswordProvider.notifier).setState(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Contraseña actualizada con éxito.', style: GoogleFonts.inter()),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/');
      }
    } catch (e) {
      setState(() => _errorMessage = "Error al actualizar contraseña. Inténtalo de nuevo.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.password_rounded,
                            size: 72,
                            color: Colors.white.withOpacity(0.9),
                          ).animate().fade().scale(),
                          const SizedBox(height: 16),
                          Text(
                            'Nueva Contraseña',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ).animate().fade().slideY(),
                          const SizedBox(height: 8),
                          Text(
                            'Crea tu nueva contraseña para acceder a la aplicación.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ).animate().fade(),
                          const SizedBox(height: 40),

                          if (_errorMessage != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                              ),
                              child: Text(_errorMessage!, style: GoogleFonts.inter(color: Colors.white)),
                            ),

                          // Pass
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: TextField(
                              controller: _passwordController,
                              obscureText: _obscure,
                              style: GoogleFonts.inter(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Nueva contraseña',
                                hintStyle: GoogleFonts.inter(color: Colors.white54),
                                prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: Colors.white54),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Confirm
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: TextField(
                              controller: _confirmController,
                              obscureText: _obscure,
                              style: GoogleFonts.inter(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Confirmar contraseña',
                                hintStyle: GoogleFonts.inter(color: Colors.white54),
                                prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 32),
                          
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            constraints: const BoxConstraints(minHeight: 56),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFDF00), Color(0xFFD4AF37)],
                              ),
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _updatePassword,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : Text(
                                      'Guardar Contraseña',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF001F54),
                                      ),
                                    ),
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
}
