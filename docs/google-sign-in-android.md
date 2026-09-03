# Google Sign-In en Android

La app usa autenticacion nativa de Google en Android y entrega los tokens a
Supabase. Firebase sigue usandose para FCM, pero pertenece a otro proyecto y no
define las credenciales OAuth de esta autenticacion.

## Credenciales que deben existir en Google Cloud

En el proyecto propietario del Web Client ID
`882216089330-shvij662ok8e0h1kd6o7k86id49fdf10.apps.googleusercontent.com`, crea
clientes OAuth de tipo **Android** con el paquete `com.lldm.bc` para cada firma:

| Compilacion | SHA-1 | SHA-256 |
| --- | --- | --- |
| Debug local | `6B:61:DE:F2:67:1B:6F:D9:87:42:5E:C7:83:BC:AB:CC:DA:A5:50:C3` | `99:BC:23:62:FB:4A:17:B9:1C:3E:D7:80:DB:23:B8:AB:B9:96:9D:20:68:46:CD:F6:CB:33:BC:6B:9B:95:35:58` |
| Release/subida | `B8:6C:12:58:50:58:33:7B:CD:4E:D4:4F:57:DA:6C:8A:1D:10:61:5A` | `53:1D:9D:E1:2E:C8:46:14:25:85:AE:88:F5:D5:69:8F:9E:7C:17:7D:3C:A3:69:C1:45:61:08:A8:F8:03:70:39` |

Si la app se distribuye mediante Google Play App Signing, crea un tercer
cliente Android con las huellas del certificado de firma de la app que aparecen
en Play Console, en **Configuracion > Integridad de la app**. Esa firma es la
que llevan los APK instalados desde Play Store y normalmente es distinta de la
clave de subida.

No reemplaces `android/app/google-services.json` por un archivo del proyecto
OAuth: el archivo actual tambien configura Firebase Messaging. El Web Client ID
correcto se pasa explicitamente desde Dart.

Despues de guardar los clientes OAuth, espera unos minutos y prueba tanto una
compilacion debug como una instalacion descargada desde Google Play.
