import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    
    // Animación 1: Fade-in de 800ms (Solo ocurre una vez al abrir)
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    // Animación 2: Resplandor pulsante (Infinito)
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.0, end: 25.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Seleccionar logo según el modo
    final imagePath = isDark ? 'assets/splash_icon_dark.png' : 'assets/splash_icon_light.png';
    // El color de resplandor será el color primario puro, con opacidad
    final glowColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.3);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeController,
          child: AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: glowColor,
                      blurRadius: _glowAnimation.value,
                      spreadRadius: _glowAnimation.value / 1.5,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Image.asset(
              imagePath,
              width: 140,
              height: 140,
            ),
          ),
        ),
      ),
    );
  }
}
