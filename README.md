# Repertorio BC 🎵

**Repertorio BC** es una aplicación móvil diseñada específicamente para la gestión eficiente de partituras, audios y ensayos de coros. Construida con Flutter y Supabase, permite a los músicos y directores llevar su repertorio siempre consigo, con soporte robusto para uso sin conexión (*Offline-First*) y sincronización en tiempo real.

---

## 🌟 Características Principales

*   **Visor de Partituras (PDF):** Renderizado de alto rendimiento utilizando `pdfx`, con soporte para modo de navegación dual (Desplazamiento vertical y Carrusel horizontal).
*   **Gestión Offline-First:** Las partituras y metadatos se descargan y almacenan en caché localmente (`Hive` + sistema de archivos). La app funciona perfectamente sin conexión a internet durante ensayos o presentaciones en lugares sin señal.
*   **Reproductor MIDI Integrado:** Permite a los cantantes escuchar sus voces por separado durante el ensayo de la partitura.
*   **Sistema de Roles:** Acceso segmentado para Directores, Subdirectores, Miembros y Superadmins.
*   **Sincronización en Vivo:** Los directores pueden "transmitir" comandos (como cambiar de página) a todos los miembros de su coro en tiempo real usando WebSockets.
*   **Perfiles de Diseño:** Modo Claro, Oscuro y Modo Lectura (Sepia/Quiet) para reducir la fatiga visual bajo iluminación de escenario.

---

## 🛠️ Stack Tecnológico

*   **Frontend:** Flutter (Dart)
*   **Backend & Auth:** Supabase (PostgreSQL, Auth, Storage, Realtime)
*   **Gestión del Estado:** Riverpod 2.0 (Generadores e inyección de dependencias)
*   **Enrutamiento:** GoRouter (Con soporte nativo para deep links y protección de rutas)
*   **Base de Datos Local:** Hive (NoSQL, rápida y síncrona para configuraciones)
*   **Notificaciones Push:** Firebase Cloud Messaging (FCM)

---

## 🚀 Instalación y Configuración Local

### Prerrequisitos
*   [Flutter SDK](https://flutter.dev/docs/get-started/install) (Versión recomendada: 3.19 o superior)
*   Un proyecto en [Supabase](https://supabase.com) y en [Firebase](https://firebase.google.com)
*   Git

### Paso a paso

1. **Clonar el repositorio:**
   ```bash
   git clone <URL_DEL_REPOSITORIO>
   cd repertorio_bc
   ```

2. **Instalar dependencias:**
   ```bash
   flutter pub get
   ```

3. **Configurar variables de entorno:**
   Deberás configurar las credenciales de Supabase en `lib/core/supabase/supabase_service.dart` (o donde se estén inyectando actualmente en tu entorno local).

4. **Ejecutar el generador de Riverpod (si vas a modificar estado):**
   ```bash
   dart run build_runner watch -d
   ```

5. **Lanzar la aplicación:**
   ```bash
   flutter run
   ```

---

## 📖 Documentación Adicional

Para más detalles sobre la arquitectura, convenciones de código y la hoja de ruta del proyecto, consulta nuestra:

👉 **[Guía de Desarrollo y Arquitectura](GUIA_DESARROLLO.md)**

---

*Desarrollado con ❤️ para los coros de Baja California.*
