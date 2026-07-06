import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GestorScreen extends StatefulWidget {
  const GestorScreen({super.key});

  @override
  State<GestorScreen> createState() => _GestorScreenState();
}

class _GestorScreenState extends State<GestorScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            if (_isLoading) {
              final session = Supabase.instance.client.auth.currentSession;
              if (session != null) {
                final sessionStr = jsonEncode(session.toJson());
                await _controller.runJavaScript('''
                  try {
                    const key = 'sb-mxnhmtztxgeccohlgqpt-auth-token';
                    if (!localStorage.getItem(key)) {
                      localStorage.setItem(key, JSON.stringify($sessionStr));
                      window.location.reload();
                    }
                    
                    // Inyectar CSS para ocultar elementos redundantes en la app nativa
                    const style = document.createElement('style');
                    style.innerHTML = `
                      #btn-ir-publico, 
                      #btn-cerrar-sesion,
                      .logo-app,
                      #usuario-rol {
                        display: none !important;
                      }
                      /* Reducir espacio superior e izquierdo sobrante */
                      .topbar { padding-left: 10px !important; }
                      .topbar-izq { width: auto !important; margin-right: 15px !important; }
                    `;
                    document.head.appendChild(style);
                  } catch(e) { console.error(e); }
                ''');
              }
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.lldmcorobc.com/gestor.html'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Administración',
          style: GoogleFonts.inter(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            ),
        ],
      ),
    );
  }
}
