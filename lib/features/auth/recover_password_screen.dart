import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecoverPasswordScreen extends StatefulWidget {
  const RecoverPasswordScreen({super.key});

  @override
  State<RecoverPasswordScreen> createState() => _RecoverPasswordScreenState();
}

class _RecoverPasswordScreenState extends State<RecoverPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _success = false;

  Future<void> _recover() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = "Por favor, ingresa tu correo.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'repertoriobc://reset-callback/',
      );
      setState(() => _success = true);
    } catch (e) {
      setState(() => _errorMessage = "Ocurrió un error al intentar enviar el enlace.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fondo
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
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.lock_reset_rounded,
                            size: 72,
                            color: Colors.white.withValues(alpha: 0.9),
                          ).animate().fade().scale(),
                          const SizedBox(height: 16),
                          Text(
                            'Recuperar',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ).animate().fade().slideY(),
                          const SizedBox(height: 8),
                          Text(
                            'Ingresa tu correo y te enviaremos un enlace para restablecer tu contraseña.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ).animate().fade(),
                          const SizedBox(height: 40),

                          if (_success)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                "Enlace enviado. Revisa tu bandeja de entrada.",
                                style: GoogleFonts.inter(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            )
                          else ...[
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

                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: GoogleFonts.inter(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Correo electrónico',
                                  hintStyle: GoogleFonts.inter(color: Colors.white54),
                                  prefixIcon: const Icon(Icons.email_outlined, color: Colors.white70),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                ),
                              ),
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
                                onPressed: _isLoading ? null : _recover,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : Text(
                                        'Enviar Enlace',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF001F54),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 24),
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
}
