# Guía de desarrollo

Guía práctica para mantener y ampliar Repertorio BC sin perder consistencia entre la aplicación Flutter, el backend Supabase y los recursos nativos.

## 1. Visión general

Repertorio BC es una aplicación Flutter/Dart para consultar y administrar partituras PDF y archivos MIDI de coros. La aplicación usa Supabase para autenticación, datos, funciones RPC y Realtime; conserva en caché información y archivos autorizados para permitir el uso offline.

El punto de entrada es `lib/main.dart`. Antes de montar la interfaz inicializa:

- Supabase;
- caché local de la aplicación;
- notificaciones push/locales;
- configuración de pantalla y ejecución edge-to-edge.

La aplicación se monta dentro de `ProviderScope` y utiliza `MaterialApp.router`.

## 2. Organización del código

```text
lib/
├── app/
│   ├── app.dart       # MaterialApp, temas y accesibilidad de texto
│   └── router.dart    # GoRouter, rutas protegidas y deep links
├── core/
│   ├── activity/      # Registro de accesos y actividad
│   ├── midi/          # Parser, reproducción y exportación MIDI
│   ├── notifications/ # Firebase Messaging y notificaciones locales
│   ├── offline/       # Descarga, caché, versiones y reparación de archivos
│   ├── pdf/           # Estado del visor y anotaciones
│   ├── providers/     # Estado de auth, repertorio, eventos, favoritos y tema
│   ├── realtime/      # Suscripciones a cambios de Supabase
│   ├── security/      # Validación y descifrado de archivos compatibles
│   ├── storage/       # Caché y guardado de archivos en el dispositivo
│   └── supabase/      # Inicialización del cliente Supabase
├── features/
│   ├── auth/          # Inicio de sesión, registro y recuperación
│   ├── dashboard/     # Repertorio, búsqueda y filtros
│   ├── gestor/        # Administración de sedes, cantos, eventos y miembros
│   ├── jukebox/       # Ruta reservada; pantalla actual de ejemplo
│   ├── settings/      # Cuenta, notificaciones, tema y sincronización
│   ├── splash/        # Arranque de la aplicación
│   └── visor/         # PDF, anotaciones, MIDI, compartir y transmisión
└── models/            # Canto, evento, perfil y trazos de anotación
```

Los recursos estáticos están en `assets/`. El código nativo o dependencias mantenidas localmente están en `android/`, `ios/` y `third_party/`. Las migraciones del backend viven en `supabase/migrations/`.

## 3. Estado y dependencias

El estado de la aplicación usa Riverpod con `Provider`, `FutureProvider`, `StreamProvider`, `NotifierProvider` y `AsyncNotifier`. No hay una carpeta de código generado ni un paso obligatorio de `build_runner` en el proyecto actual.

Reglas recomendadas:

- Mantener en providers el estado compartido y la lógica que cruza pantallas.
- Mantener en widgets el estado estrictamente visual o temporal.
- Invalidar o actualizar providers después de mutaciones en Supabase.
- No almacenar datos de un usuario en claves globales: usar `AppCache.userKey(...)`.
- No leer directamente el estado de otro módulo si existe un provider para ese propósito.
- Liberar controladores, streams, reproductores y suscripciones en `dispose`.

## 4. Navegación y autenticación

Las rutas se centralizan en `lib/app/router.dart`. El redirect global:

- muestra splash mientras se resuelve el estado inicial;
- envía a login a usuarios no autenticados;
- dirige a actualización de contraseña durante recuperación;
- solicita completar el perfil cuando el acceso con Google no tiene perfil;
- protege `/gestor` por rol;
- procesa enlaces de evento y enlaces que abren un canto;
- abre el visor cuando una notificación contiene un `canto_id`.

Al agregar una ruta protegida, valida si requiere sesión, perfil cargado o un rol específico. La autorización real debe existir también en Supabase mediante RLS o funciones RPC; el redirect de Flutter solo es una capa de navegación.

## 5. Datos y backend

El cliente usa Supabase para consultar, entre otras, las entidades:

- `perfiles`;
- `coros`;
- `cantos` y `cantos_coros`;
- `eventos` y `eventos_cantos`;
- `suscripciones_push`;
- `accesos_app`;
- `errores_app`.

Las operaciones administrativas importantes pasan por funciones RPC con validación de usuario, rol, sede y estado. Las migraciones actuales incluyen registro de accesos, eliminación de cuenta, usuario independiente, catálogo global bilingüe y mutaciones atómicas del gestor.

Al cambiar el esquema:

1. crea una migración nueva con prefijo de fecha;
2. haz que sea segura si se ejecuta en un entorno ya actualizado;
3. actualiza las consultas y modelos Dart;
4. revisa RLS y permisos de las funciones;
5. actualiza las pruebas relacionadas.

No edites migraciones ya aplicadas para corregir datos históricos.

## 6. Repertorio y modo offline

`cantos_provider.dart` obtiene el repertorio autorizado para la sede del perfil y el catálogo estatal/global, lo normaliza, filtra y deduplica por identidad del PDF.

`SyncManagerNotifier` coordina la descarga de PDF y MIDI. `OfflineFiles`:

- resuelve la URL del recurso;
- compara la versión local con la del catálogo;
- descarga desde las rutas disponibles;
- valida el tipo de archivo;
- descifra recursos compatibles cuando corresponde;
- conserva el archivo en el directorio de documentos;
- elimina cachés que ya no están autorizadas;
- usa memoria temporal si no hay espacio suficiente.

No supongas que todo el catálogo está disponible offline. Solo se sincroniza el repertorio autorizado y los archivos que hayan terminado la descarga.

## 7. Visor PDF y anotaciones

El visor se implementa en `features/visor/visor_screen.dart` y delega el estado del documento a `PdfEngineNotifier`.

Al modificarlo:

- conserva la diferencia entre desplazamiento vertical y carrusel;
- no bloquees el gesto de navegación cuando el usuario no está dibujando;
- transforma las coordenadas de anotación con el tamaño real de la página;
- usa el historial existente para deshacer y rehacer;
- libera bytes temporales al salir del visor;
- no presentes las anotaciones como sincronizadas: actualmente viven en el estado de la sesión.

## 8. Motor MIDI

`MidiEngine` es un singleton de reproducción. Carga archivos locales, parsea pistas, reproduce notas, controla velocidad, metrónomo, mute, solo y volumen por voz.

`MidiExportService` permite crear MP3 del ensamble o de una voz. Al cambiar el motor:

- detén notas activas al pausar, detener o cargar otro archivo;
- libera reproductores y timers;
- mantén el control de velocidad coherente con el metrónomo;
- prueba MIDI sin pistas, con cambios de tempo y con varias voces;
- usa los recursos de `assets/Piano.sf2` y `assets/audio/metro/`.

La ruta `/jukebox` existe, pero su pantalla actual es un placeholder y no debe documentarse como funcionalidad terminada.

## 9. Realtime y notificaciones

`RealtimeManager` conecta la sede del perfil a los cambios relevantes de Supabase. Las notificaciones usan Firebase Messaging cuando la plataforma y sus permisos están configurados, junto con notificaciones locales.

Toda notificación debe tratarse como opcional:

- la app debe seguir funcionando si no hay token;
- no asumas que el permiso fue concedido;
- valida el payload antes de navegar;
- evita duplicar avisos al registrar errores;
- no guardes tokens en logs.

## 10. Gestor administrativo

El Gestor Admin está en `features/gestor/` y ofrece administración de cantos, catálogo global, eventos, miembros, roles, presencia, actividad y recordatorios.

Las operaciones de escritura deben usar el repositorio existente y las funciones atómicas del backend. No agregues escrituras directas que permitan saltarse la validación de sede o rol.

## 11. Temas, accesibilidad y UX

Los temas y colores se gestionan desde `theme_provider.dart`. La app soporta modo claro, oscuro, sepia y quiet, además de escalado de texto limitado por la configuración de accesibilidad.

Antes de cerrar una pantalla:

- verifica contraste en los cuatro modos;
- añade tooltip a acciones de icono;
- conserva estados de carga, vacío y error;
- evita depender únicamente del color;
- prueba tamaños de texto grandes;
- confirma que los diálogos y hojas se puedan cerrar sin perder cambios.

## 12. Pruebas y comandos

Antes de enviar cambios:

```bash
flutter pub get
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
```

Pruebas existentes cubren caché, modelo de cantos, catálogo, mutaciones del gestor, motor MIDI, archivos offline, single-flight y smoke test de widgets.

Para compilar:

```bash
flutter build apk --release
flutter build appbundle --release
flutter build ios --release --no-codesign
flutter build web --release
```

## 13. Git y CI

Usa ramas descriptivas con el prefijo `codex/` cuando trabajes con este flujo. Mantén commits pequeños y explica cambios de código, migraciones, permisos o configuración nativa.

El workflow `.github/workflows/ios_build.yml` instala Flutter 3.32.4, analiza, ejecuta pruebas, instala CocoaPods y compila iOS. La firma, exportación y carga a App Store Connect solo ocurren cuando existen los secretos correspondientes.

## 14. Seguridad y configuración

La URL y la clave publicable de Supabase se leen en `lib/core/supabase/supabase_service.dart`. Las credenciales publicables no sustituyen RLS ni la autorización del backend.

Nunca subas:

- claves privadas;
- certificados de firma;
- claves de App Store Connect;
- secretos de Firebase;
- tokens de usuarios;
- dumps de producción.

Antes de publicar, revisa `android/`, `ios/`, Firebase/APNs, las migraciones y las políticas de Supabase. La aplicación valida archivos PDF/MIDI y puede procesar recursos cifrados, pero la documentación no debe prometer una arquitectura de cifrado que no esté implementada y auditada de extremo a extremo.
