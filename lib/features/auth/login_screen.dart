import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'dart:async';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  
  // Anti-Brute Force
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  Timer? _countdownTimer;
  String _lockoutMessage = '';

  @override
  void initState() {
    super.initState();
    _checkLockoutStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  void _checkLockoutStatus() {
    final box = Hive.box('cache');
    _failedAttempts = box.get('login_failed_attempts', defaultValue: 0);
    final lockoutMillis = box.get('login_lockout_until');
    
    if (lockoutMillis != null) {
      final lockoutTime = DateTime.fromMillisecondsSinceEpoch(lockoutMillis);
      if (lockoutTime.isAfter(DateTime.now())) {
        _lockoutUntil = lockoutTime;
        _startCountdown();
      } else {
        // Expiró el castigo
        box.delete('login_lockout_until');
        box.put('login_failed_attempts', 0);
        _failedAttempts = 0;
      }
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _updateLockoutMessage();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_lockoutUntil == null || DateTime.now().isAfter(_lockoutUntil!)) {
        timer.cancel();
        setState(() {
          _lockoutUntil = null;
          _lockoutMessage = '';
          _failedAttempts = 0;
        });
        final box = Hive.box('cache');
        box.delete('login_lockout_until');
        box.put('login_failed_attempts', 0);
      } else {
        _updateLockoutMessage();
      }
    });
  }

  void _updateLockoutMessage() {
    if (_lockoutUntil == null) return;
    final diff = _lockoutUntil!.difference(DateTime.now());
    final minutes = diff.inMinutes;
    final seconds = diff.inSeconds % 60;
    setState(() {
      _lockoutMessage = 'Demasiados intentos. Intenta en ${minutes}m ${seconds}s';
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      return; // Bloqueado
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthController.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) {
        TextInput.finishAutofillContext();
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        _failedAttempts++;
        final box = Hive.box('cache');
        
        if (_failedAttempts >= 5) {
          final lockoutTime = DateTime.now().add(const Duration(minutes: 3));
          _lockoutUntil = lockoutTime;
          box.put('login_lockout_until', lockoutTime.millisecondsSinceEpoch);
          _startCountdown();
          setState(() {
            _errorMessage = null; // Reemplazado por el mensaje de lockout
          });
        } else {
          box.put('login_failed_attempts', _failedAttempts);
          setState(() {
            _errorMessage = "Credenciales incorrectas. Te quedan ${5 - _failedAttempts} intentos.";
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });

    return Scaffold(
      body: Stack(
        children: [
          // Fondo gradiente animado y premium
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF001533), Color(0xFF0033A0), Color(0xFF0F52BA)], // Azul Rey profundo
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          // Circulos decorativos de fondo (Glassmorphism effect support)
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4AF37).withOpacity(0.15), // Círculo dorado
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .scale(duration: 4.seconds, begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1)),
          ),
          Positioned(
            bottom: -150,
            right: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0055FF).withOpacity(0.1), // Círculo azul vibrante
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .move(duration: 5.seconds, begin: const Offset(0, 20), end: const Offset(0, -20)),
          ),

          // Contenido principal
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
                      child: AutofillGroup(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.music_note_rounded,
                              size: 72,
                              color: Colors.white.withOpacity(0.9),
                            ).animate().fade(duration: 600.ms).scale(delay: 200.ms),
                            const SizedBox(height: 16),
                            Text(
                              'Repertorio BC',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ).animate().fade(delay: 300.ms).slideY(begin: 0.2, end: 0),
                            const SizedBox(height: 8),
                            Text(
                              'Acceso exclusivo para coros',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.white70,
                                fontWeight: FontWeight.w400,
                              ),
                            ).animate().fade(delay: 400.ms),
                            const SizedBox(height: 48),

                            if (_lockoutUntil != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 24),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.lock_clock_outlined, color: Colors.orangeAccent, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _lockoutMessage,
                                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ).animate().shake(hz: 4)
                            else if (_errorMessage != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 24),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: GoogleFonts.inter(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ).animate().shake(hz: 4),

                            // Email Field
                            _buildTextField(
                              controller: _emailController,
                              hintText: 'Correo electrónico',
                              icon: Icons.alternate_email_rounded,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                            ).animate().fade(delay: 500.ms).slideX(begin: -0.1, end: 0),
                            const SizedBox(height: 20),
                            
                            // Password Field
                            _buildTextField(
                              controller: _passwordController,
                              hintText: 'Contraseña',
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscurePassword,
                              keyboardType: TextInputType.visiblePassword,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _login(),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.white70),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ).animate().fade(delay: 600.ms).slideX(begin: -0.1, end: 0),
                            
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => context.push('/recover'),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                child: Text(
                                  '¿Olvidaste tu contraseña?',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: const Color(0xFFD4AF37), // Dorado
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ).animate().fade(delay: 650.ms),
                            
                            const SizedBox(height: 32),
                            
                            // Login Button
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              constraints: const BoxConstraints(minHeight: 56),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  colors: _lockoutUntil != null
                                      ? [Colors.grey.shade700, Colors.grey.shade800]
                                      : [const Color(0xFFFFDF00), const Color(0xFFD4AF37)], // Dorado degradado
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                boxShadow: _lockoutUntil != null ? [] : [
                                  BoxShadow(
                                    color: const Color(0xFFD4AF37).withOpacity(0.3), // Sombra dorada
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  )
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: (_isLoading || _lockoutUntil != null) ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  disabledForegroundColor: Colors.white60,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Text(
                                        _lockoutUntil != null ? 'Bloqueado temporalmente' : 'Iniciar Sesión',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: _lockoutUntil != null ? Colors.white60 : const Color(0xFF001533),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            ).animate().fade(delay: 700.ms).slideY(begin: 0.2, end: 0),
                            
                            const SizedBox(height: 16),
                            
                            // Botón de Google
                            Container(
                              constraints: const BoxConstraints(minHeight: 52),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _isLoading ? null : () {
                                  setState(() => _isLoading = true);
                                  AuthController.loginWithGoogle().catchError((e) {
                                    if (mounted) {
                                      setState(() {
                                        _isLoading = false;
                                        _errorMessage = 'Error con Google: $e';
                                      });
                                    }
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                icon: const Icon(Icons.g_mobiledata_rounded, color: Colors.black87, size: 32),
                                label: Text(
                                  'Continuar con Google',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ).animate().fade(delay: 750.ms).slideY(begin: 0.2, end: 0),

                            const SizedBox(height: 24),
                            
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '¿No tienes cuenta?',
                                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                                ),
                                TextButton(
                                  onPressed: () => context.push('/register'),
                                  child: Text(
                                    'Solicitar Acceso',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ).animate().fade(delay: 800.ms),
                          ],
                        ),
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
    Iterable<String>? autofillHints,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
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
}
