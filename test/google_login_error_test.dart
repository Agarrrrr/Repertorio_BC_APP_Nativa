import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';

void main() {
  group('GoogleLoginException', () {
    test('explica un error de configuracion OAuth', () {
      final error = GoogleLoginException.fromGoogle(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        ),
      );

      expect(error.message, contains('certificado SHA'));
    });

    test('advierte que una cancelacion tambien puede ser una firma faltante',
        () {
      final error = GoogleLoginException.fromGoogle(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
      );

      expect(error.message, contains('despues de elegir una cuenta'));
      expect(AuthController.googleLoginErrorMessage(error), error.message);
    });

    test('no muestra detalles internos para un error desconocido', () {
      expect(
        AuthController.googleLoginErrorMessage(Exception('internal error')),
        'No se pudo iniciar sesion con Google. Intenta de nuevo.',
      );
    });
  });
}
