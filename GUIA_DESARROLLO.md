# Guía de Desarrollo y Arquitectura 🏗️

Esta guía proporciona una visión profunda de cómo está estructurada la aplicación **Repertorio BC** y las convenciones a seguir durante su desarrollo.

---

## 1. Arquitectura del Proyecto

El proyecto sigue una estructura modular basada en características (*Feature-First*), lo que significa que el código se agrupa por su dominio funcional en lugar de su tipo técnico (ej. no tenemos carpetas globales enormes de `models`, `views`, `controllers`).

```
lib/
├── app/                  # Configuración global, router, temas.
├── core/                 # Servicios globales (Supabase, Hive, Riverpod providers base).
├── features/             # Módulos funcionales de la app.
│   ├── auth/             # Login, registro, recuperación.
│   ├── dashboard/        # Pantalla principal, menús.
│   ├── settings/         # Ajustes de la app.
│   └── visor/            # Lógica central: renderizado de PDF, MIDI, Live Sync.
├── models/               # Modelos de datos compartidos (Perfil, Canto, Coro).
└── main.dart             # Punto de entrada, inicialización de dependencias (Hive, Supabase).
```

---

## 2. Decisiones Clave de Diseño Técnico

### A. Gestión del Estado (Riverpod)
Utilizamos **Riverpod** para el estado y la inyección de dependencias. 
*   No se usa `StatefulWidget` a menos que sea estrictamente necesario para animaciones o controladores locales (`TextEditingController`, `AnimationController`).
*   Todo el estado de negocio y la lógica de autenticación fluye a través de Providers (`NotifierProvider`, `StreamProvider`, `FutureProvider`).

### B. Enrutamiento (GoRouter)
Se usa **GoRouter** para manejar la navegación. 
*   `routerProvider` centraliza las redirecciones globales (si el usuario no está logueado, lo saca; si lo está, lo envía al Dashboard).
*   Se implementa `refreshListenable` para que el router reaccione en tiempo real a cambios en el `authUserProvider`.

### C. Estrategia Offline-First
Para garantizar que los músicos puedan usar la app en escenarios sin cobertura:
*   Se utiliza `SyncManagerNotifier` para pre-descargar (prefetch) y cachear los archivos (PDFs y MIDIs).
*   Se utiliza `path_provider` para guardar los binarios y `Hive` para cachear respuestas JSON de la base de datos (como el catálogo de cantos y perfiles).

### D. Optimización de Renderizado (PDF)
El visor de partituras (en `visor_screen.dart`) es el componente más intensivo:
*   Para evitar caídas de FPS (*Paint Storms*), se recomienda el uso de `RepaintBoundary` en listas complejas.
*   El visor gestiona eficientemente la memoria liberando documentos PDF cuando el componente se destruye.

---

## 3. Convenciones de Código

1. **Inmutabilidad:** Todos los modelos (ej. `Perfil`, `Canto`) usan `final` en todas sus propiedades y tienen métodos `copyWith`.
2. **Null Safety:** Strict null safety. Las comprobaciones de nulos (`?.`) innecesarias deben evitarse, aprovechando el análisis de flujo de Dart.
3. **Manejo de UI:** Usa `flutter_animate` para micro-interacciones (fades, slides). Se prefieren los diseños limpios tipo *Glassmorphism* y gradientes sutiles que refuercen una apariencia premium.
4. **Mensajes Consola / Errores:** Evita usar `print()`. Para errores graves en producción o flujos asíncronos, se deberá usar servicios de recolección (como Crashlytics o manejo propio) y notificar al usuario de forma amigable (Snackbars nativos o diálogos).

---

## 4. Flujo de Trabajo (Git)

1. Crear ramas basadas en `feature/nombre-de-la-caracteristica` o `fix/descripcion-del-bug`.
2. Mantener los *commits* granulares y descriptivos.
3. Asegurarse de ejecutar `flutter analyze` antes de enviar cambios al repositorio remoto.
