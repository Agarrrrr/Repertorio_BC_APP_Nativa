# Repertorio BC

Aplicación multiplataforma para organizar, estudiar y presentar el repertorio musical de coros. Reúne partituras PDF, archivos MIDI, herramientas de ensayo, distribución por voces y administración de sedes, con soporte para trabajar sin conexión.

> Estado actual: versión `2.6.1+43`.

## Capacidades

### Repertorio y búsqueda

- Catálogo organizado por **coro local** y **catálogo estatal**.
- Catálogo global bilingüe para localizar material y añadirlo a una sede.
- Búsqueda por título con normalización de texto y ordenamiento natural.
- Filtros por temas, carpetas/eventos y favoritos.
- Deduplicación por PDF y actualización del repertorio desde Supabase.

### Visor de partituras

- Lectura PDF con navegación vertical o carrusel horizontal.
- Temas claro, oscuro y modos de lectura sepia/quiet.
- Anotaciones sobre la partitura: lápiz, texto, borrador, color, tamaño, deshacer, rehacer y limpieza por página o documento.
- Compartir el PDF desde el dispositivo.
- Enlaces profundos y notificaciones que abren directamente un canto.

### Ensayo MIDI

Cuando un canto tiene MIDI asignado, el visor ofrece:

- reproducción, pausa, detención y búsqueda;
- ajuste de velocidad;
- metrónomo sincronizado con tempo, compás y subdivisión;
- mezclador de voces con volumen independiente;
- activar/desactivar voces y modo solo;
- ensamble y voces individuales;
- SoundFont de piano incluido.

El MIDI también puede convertirse a MP3 del ensamble o de voces individuales para guardarlo o compartirlo.

### Trabajo sin conexión

- Descarga automática de PDF y MIDI del repertorio autorizado.
- Caché local por usuario para ensayos sin internet.
- Verificación de versiones y reparación manual desde Ajustes.
- Descargas controladas para evitar transferencias duplicadas.
- Manejo de archivos cifrados y validación básica PDF/MIDI.
- Indicador de sincronización, progreso, errores y espacio disponible.

El modo offline requiere una sincronización previa. Los cambios administrativos y la información en tiempo real requieren conexión.

### Coordinación en tiempo real

- Actualización del repertorio mediante Supabase Realtime.
- Transmisión de un canto desde el visor a la sede activa.
- Recepción de cambios y avisos en vivo.
- Enlaces de eventos para abrir carpetas compartidas y vincular participantes autorizados.

### Cuentas, roles y notificaciones

- Registro, inicio de sesión con correo o Google, recuperación y cambio de contraseña.
- Completar perfil después del primer acceso con Google.
- Cierre de sesión y eliminación permanente de cuenta.
- Rutas protegidas por autenticación y rol.
- Roles: miembro, delegado, subdirector, director, director estatal y superadmin.
- Gestor Admin restringido a roles autorizados.
- Registro de tokens, notificaciones push/locales, historial y apertura directa del canto relacionado.
- Gestión explícita de permisos denegados o plataformas sin soporte push.

### Gestión administrativa

El panel **Gestor Admin** permite:

- seleccionar la sede administrada;
- crear, editar y eliminar partituras propias;
- cargar o reemplazar PDF y MIDI;
- consultar el catálogo global y añadir material a una sede;
- previsualizar partituras;
- crear carpetas/eventos y asignarles cantos;
- consultar miembros, activarlos, suspenderlos y cambiar roles;
- ver presencia, usuarios conectados y distribución de voces;
- revisar vistas, actividad y alertas técnicas;
- enviar recordatorios a la sede seleccionada.

## Arquitectura y tecnologías

- **Cliente:** Flutter y Dart.
- **Estado:** Flutter Riverpod.
- **Navegación:** GoRouter, rutas protegidas y deep links.
- **Backend:** Supabase Auth, PostgreSQL, Storage y Realtime.
- **Archivos:** servicio de almacenamiento para PDF/MIDI.
- **Persistencia local:** Hive y directorio de documentos.
- **PDF:** `pdfrx`.
- **Audio:** motor MIDI nativo, SoundFont local y `audioplayers`.
- **Exportación:** WAV/MP3 con `flutter_lame` incluido en `third_party/`.
- **Notificaciones:** Firebase Messaging y notificaciones locales.
- **Compartir:** `share_plus`.
- **CI/CD:** GitHub Actions para análisis, pruebas y build iOS.

## Estructura

```text
lib/
├── app/              # Tema, router y configuración
├── core/             # Auth, Supabase, caché, offline, MIDI, PDF y notificaciones
├── features/         # Auth, dashboard, visor, gestor y ajustes
└── models/           # Canto, perfil, evento y anotaciones

assets/               # SoundFont, sonidos, MIDI y splash
supabase/migrations/  # Migraciones SQL
test/                 # Pruebas unitarias, integración y widgets
android/              # Proyecto Android
ios/                  # Proyecto iOS
web/                  # Landing, soporte y privacidad
third_party/          # Dependencias nativas incluidas
```

## Requisitos

- Flutter estable compatible con Dart `3.5.0` o superior. El pipeline usa Flutter `3.32.4`.
- Android Studio/SDK para Android.
- Xcode y CocoaPods para iOS.
- Git.
- Proyecto Supabase con Auth, base de datos, Storage/servicio de archivos y Realtime.
- Firebase y configuración nativa si se requieren notificaciones push.

## Instalación

```bash
git clone <URL_DEL_REPOSITORIO>
cd repertorio_bc
flutter pub get
flutter run
```

Plataformas:

```bash
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

## Configuración de servicios

Revisa antes de una instalación nueva:

- `lib/core/supabase/supabase_service.dart`: URL pública y clave publicable de Supabase.
- `lib/core/notifications/push_service.dart`: Firebase Messaging y permisos.
- `android/` e `ios/`: configuración Firebase/APNs.
- `supabase/migrations/`: esquema y funciones RPC requeridas.

Las políticas RLS, funciones RPC, permisos de Storage y secretos de servidor deben configurarse en el backend. No publiques credenciales privadas, certificados ni claves de firma.

## Desarrollo y verificación

```bash
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
```

Compilaciones:

```bash
flutter build apk --release
flutter build appbundle --release
flutter build ios --release --no-codesign
flutter build web --release
```

El workflow `.github/workflows/ios_build.yml` instala dependencias, analiza, ejecuta pruebas, compila iOS y firma/exporta la IPA o la sube a App Store Connect cuando están configurados los secretos de Apple.

## Alcance actual

- La ruta `/jukebox` existe, pero su pantalla actual es un placeholder; no se presenta como funcionalidad terminada.
- Las anotaciones del visor se gestionan durante la sesión actual y no se documentan como sincronizadas entre dispositivos.
- Push depende de permisos del sistema y configuración Firebase/APNs.
- Offline cubre archivos autorizados y sincronizados previamente.
- En entornos nuevos deben aplicarse las migraciones y validarse las políticas de acceso antes de publicar.

## Documentación

- [Guía de desarrollo](GUIA_DESARROLLO.md)
- [Soporte](web/soporte.html)
- [Política de privacidad](web/privacy.html)
- [Respuesta para revisión de App Store](APP_STORE_REVIEW_RESPONSE.md)

## Contribuir

1. Crea una rama descriptiva.
2. Mantén los cambios enfocados y actualiza las pruebas.
3. Ejecuta análisis y pruebas antes de abrir un pull request.
4. Documenta cambios de permisos, migraciones, archivos nativos o servicios.

## Licencia

El proyecto está configurado como aplicación privada (`publish_to: none`). La licencia y permisos de distribución deben definirse con el propietario antes de publicar o reutilizar el código.

---

Desarrollado para facilitar la preparación y coordinación del repertorio coral de Baja California.
